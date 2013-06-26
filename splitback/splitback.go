package splitback

import (
	"appengine"
	"appengine/datastore"
	"appengine/mail"
	"appengine/user"
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strconv"
	"strings"
	"text/template"
	"time"
)

type Config struct {
	User        string
	Password    string
	Signature   string
	AppId       string
	AppUrl      string
	PayKeyUrl   string
	PayFormUrl  string
	EmailPrefix string
}

var config Config = Config{}
var env map[string]string

func init() {
	http.HandleFunc("/rest/signup", signup)
	http.HandleFunc("/rest/finduser", findUser)
	http.HandleFunc("/rest/remove", remove)
	http.HandleFunc("/rest/bill", bill)
	http.HandleFunc("/rest/paySucceeded", paySucceeded)
	http.HandleFunc("/rest/payFailed", payFailed)
	http.HandleFunc("/rest/payIpn", payIpn)
	http.HandleFunc("/rest/name", name)
	http.HandleFunc("/rest/owed", owed)
	http.HandleFunc("/rest/owe", owe)
	http.HandleFunc("/rest/payments", payments)
	http.HandleFunc("/rest/updateNote", updateNote)
	http.HandleFunc("/rest/updateName", updateName)

	env = getEnv()

	var configFile = "priv/paypal.json"
	if strings.Contains(env["SERVER_SOFTWARE"], "Development") {
		configFile = "priv/sandbox.json"
	}

	raw, err := ioutil.ReadFile(configFile)
	if err != nil {
		panic(err)
	}
	if err := json.Unmarshal(raw, &config); err != nil {
		panic(err)
	}
}

func getEnv() (env map[string]string) {
	env = make(map[string]string)

	vals := os.Environ()
	for _, v := range vals {
		kv := strings.SplitN(v, "=", 2)
		switch len(kv) {
		case 1:
			env[v] = ""
		case 2:
			env[kv[0]] = kv[1]
		}
	}

	return
}

type User struct {
	Name  string
	Email string
}

func signup(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	current := user.Current(c)
	u := User{
		Name:  r.FormValue("name"),
		Email: current.Email,
	}
	if _, err := datastore.Put(c, datastore.NewIncompleteKey(c, "Users", nil), &u); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/", http.StatusFound)
}

func name(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	user, _ := getUserBy(c, "Email", user.Current(c).Email)

	result := make(map[string]interface{})
	if user == nil {
		result["name"] = nil
	} else {
		result["name"] = user.Name
	}

	encoder := json.NewEncoder(w)
	encoder.Encode(result)
}

func findUser(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Sender =", key).
		Order("-Timestamp")

	friends := make(map[*datastore.Key]bool)
	for t := q.Run(c); ; {
		var bill Bill
		_, err := t.Next(&bill)
		if err == datastore.Done {
			break
		}
		if err != nil {
			panic(err)
		}

		for _, recipient := range bill.Receivers {
			friends[recipient] = true
		}
	}


	var keys = make([]*datastore.Key, len(friends))
	i := 0
	for k := range friends {
		keys[i] = k
		i++
	}

	users := make([]User, len(keys))
	err := datastore.GetMulti(c, keys, users)
	if err != nil {
		panic(err)
	}

	names := make(map[string]string)
	for i, u := range users {
		names[u.Name] = keys[i].Encode()
	}

	encoder := json.NewEncoder(w)
	encoder.Encode(names)
}

type Bill struct {
	Sender    *datastore.Key
	Receivers []*datastore.Key
	Amounts   []float32
	DatePaid  []time.Time
	Timestamp time.Time
	Note      string
}

func getUserBy(c appengine.Context, by string, value string) (user *User, key *datastore.Key) {
	q := datastore.NewQuery("Users").
		Filter(fmt.Sprintf("%s =", by), value)
	var users []User
	keys, err := q.GetAll(c, &users)
	if err != nil {
		panic(err)
	}

	//assert only one
	if len(users) == 0 {
		return nil, nil
	} else if len(users) == 1 {
		return &users[0], keys[0]
	} else {
		panic("Too many results")
	}

	return
}

func bill(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	tmpl, _ := template.ParseFiles("templates/new-bill.email")

	body := parseJsonBody(r)
	recipients := body["recipients"].([]interface{})

	sender, sender_key := getUserBy(c, "Email", user.Current(c).Email)

	receivers := make([]*datastore.Key, 0)
	amounts := make([]float32, 0)
	paid := make([]time.Time, 0)
	for _, recipient := range recipients {
		recipient := recipient.(map[string]interface{})
		if recipient["value"] == "" {
			continue
		}

		user := &User{}
		var key *datastore.Key
		if mkey, ok := recipient["key"]; ok && mkey != nil {
			var err error
			key, err = datastore.DecodeKey(mkey.(string))
			if err != nil {
				panic(err)
			}
			err = datastore.Get(c, key, user)
			if err == datastore.ErrNoSuchEntity {
				panic("unknown user key");
			}
		} else {
			value := recipient["value"].(string)
			if checkEmail(value) {
				user, key = getUserBy(c, "Email", value)
				if user == nil {
					http.Error(w, `{"error": "unknown recipient"}`,
						http.StatusBadRequest)
					return
				}
			} else {
				http.Error(w, `{"error": "invalid email"}`, http.StatusBadRequest)
				return
			}
		}

		receivers = append(receivers, key)
		amount := recipient["amount"].(float64)
		amounts = append(amounts, float32(amount))
		if recipient["paid"].(bool) {
			paid = append(paid, time.Now())
		} else {
			paid = append(paid, time.Unix(0, 0))
		}

		if !key.Equal(sender_key) {
			out := bytes.NewBuffer(nil)

			tc := map[string]interface{}{
				"Recipient": user.Name,
				"Sender":    sender.Name,
				"Amount":    strconv.FormatFloat(amount, 'f', 2, 32),
			}
			if err := tmpl.Execute(out, tc); err != nil {
				panic(err)
			}
			msg := &mail.Message{
				Sender:  "Splitback <splitbackapp@gmail.com>",
				To:      []string{user.Email},
				Subject: "You have a new bill from " + sender.Name,
				Body:    out.String(),
			}
			if err := mail.Send(c, msg); err != nil {
				c.Errorf("Couldn't send email: %v", err)
			}
		}
	}

	bill := Bill{
		Sender:    sender_key,
		Receivers: receivers,
		Amounts:   amounts,
		DatePaid:  paid,
		Timestamp: time.Now(),
	}
	if note, ok := body["note"].(string); ok {
		bill.Note = note
	}

	if _, err := datastore.Put(c, datastore.NewIncompleteKey(c, "Bills", nil), &bill); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}

func remove(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	body := parseJsonBody(r)

	key, err := datastore.DecodeKey(body["key"].(string))
	if err != nil {
		panic(err)
	}

	var bill Bill
	err = datastore.Get(c, key, &bill)
	if err == datastore.ErrNoSuchEntity {
		return
	}

	_, ukey := getUserBy(c, "Email", user.Current(c).Email)
	if !ukey.Equal(bill.Sender) {
		panic("You can't delete a bill that's not yours")
	}

	datastore.Delete(c, key)
}

func payFailed(w http.ResponseWriter, r *http.Request) {
	tmpl, _ := template.ParseFiles("templates/paypal-redirect.html")

	tc := map[string]interface{}{
		"CallbackFunction": "paymentFailed",
	}
	if err := tmpl.Execute(w, tc); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func paySucceeded(w http.ResponseWriter, r *http.Request) {
	tmpl, _ := template.ParseFiles("templates/paypal-redirect.html")

	tc := map[string]interface{}{
		"CallbackFunction": "paymentSucceeded",
	}
	if err := tmpl.Execute(w, tc); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

//TODO: Paypal's website recommends you call back to it and check
// the id of the request to ensure you're not being spoofed
func payIpn(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	sender, _ := datastore.DecodeKey(r.FormValue("Sender"))

	bills_ := strings.Split(r.FormValue("Bills"), ",")
	billKeys := make([]*datastore.Key, len(bills_))
	for i, key := range bills_ {
		billKeys[i], _ = datastore.DecodeKey(key)
	}

	bills := make([]Bill, len(billKeys))
	err := datastore.GetMulti(c, billKeys, bills)
	if err != nil {
		panic(err)
	}

	for _, bill := range bills {
		index := findInBill(&bill, sender)

		bill.DatePaid[index] = time.Now()
	}

	_, err = datastore.PutMulti(c, billKeys, bills)
	if err != nil {
		panic(err)
	}
}

func owed(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	if err := r.ParseForm(); err != nil {
		panic(err)
	}
	_, showPaid := r.Form["paid"]

	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Sender =", key).
		Order("-Timestamp")

	resp := make([]map[string]interface{}, 0)
	for t := q.Run(c); ; {
		var bill Bill
		key, err := t.Next(&bill)
		if err == datastore.Done {
			break
		}
		if err != nil {
			panic(err)
		}

		receivers := make([]User, len(bill.Receivers))
		err = datastore.GetMulti(c, bill.Receivers, receivers)
		if err != nil {
			panic(err)
		}

		all, paid := getPaid(bill.DatePaid)
		if !showPaid && all {
			continue
		}

		respReceivers := make([]map[string]interface{}, len(receivers))
		total := float32(0.0)
		for i, receiver := range receivers {
			respReceivers[i] = map[string]interface{}{
				"Name": receiver.Name,
				"Amount": bill.Amounts[i],
				"Paid": paid[i],
			}
			total += bill.Amounts[i];
		}

		resp = append(resp,
			map[string]interface{}{
			"Timestamp": bill.Timestamp.Format("Mon, Jan 02 2006 15:04:05 MST"),
			"Receivers": respReceivers,
			"Note":      bill.Note,
			"Key":       key.Encode(),
			"Total":     total,
		})
	}

	encoder := json.NewEncoder(w)
	encoder.Encode(resp)
}

func owe(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	if err := r.ParseForm(); err != nil {
		panic(err)
	}
	_, showPaid := r.Form["paid"]

	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Receivers =", key).
		Order("-Timestamp")

	resp := make([]map[string]interface{}, 0)
	for t := q.Run(c); ; {
		var bill Bill
		_, err := t.Next(&bill)
		if err == datastore.Done {
			break
		}
		if err != nil {
			panic(err)
		}
		if bill.Sender.Equal(key) {
			continue
		}

		var sender User
		err = datastore.Get(c, bill.Sender, &sender)
		if err != nil {
			panic(err)
		}

		index := findInBill(&bill, key)
		_, paid := getPaid([]time.Time{bill.DatePaid[index]})
		if !showPaid && paid[0] {
			continue
		}
		resp = append(resp,
			map[string]interface{}{
			"Timestamp": bill.Timestamp.Format("Mon, Jan 02 2006 15:04:05 MST"),
			"Sender":    sender.Name,
			"Amount":    bill.Amounts[index],
			"Paid":      paid[0],
			"Note":      bill.Note,
		})
	}

	encoder := json.NewEncoder(w)
	encoder.Encode(resp)
}

func payments(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Receivers =", key).
		Order("Sender")

	previous := Bill{}
	amount := float32(0.0)
	bills := make([]string, 0)
	first := true
	payments := make([]map[string]interface{}, 0)
	for t := q.Run(c); ; {
		var bill Bill
		billKey, err := t.Next(&bill)
		if err == datastore.Done {
			if !first {
				payments = append(payments, buildPayment(c, &previous, amount))
			}
			break
		}
		if err != nil {
			panic(err)
		}

		if bill.Sender.Equal(key) {
			continue
		}

		index := findInBill(&bill, key)

		if datePaid := bill.DatePaid[index]; datePaid.After(time.Unix(0, 0)) {
			continue
		}

		if bill.Sender.Equal(previous.Sender) || first {
			amount += bill.Amounts[index]
		} else {
			payments = append(payments, buildPayment(c, &previous, amount))
			amount = bill.Amounts[index]
		}

		bills = append(bills, billKey.Encode())

		first = false
		previous = bill
	}

	var resp map[string]interface{}
	if len(payments) == 0 {
		resp = map[string]interface{} {
			"PayKey":     "",
			"PayFormUrl": config.PayFormUrl,
			"Payments": payments,
		}
	} else {
		payKey := getPayKey(c, key, payments, bills)

		resp = map[string]interface{} {
			"PayKey":     payKey,
			"PayFormUrl": config.PayFormUrl,
			"Payments": payments,
		}
	}

	encoder := json.NewEncoder(w)
	encoder.Encode(resp)
}

func updateNote(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	body := parseJsonBody(r)

	key, err := datastore.DecodeKey(body["key"].(string))
	if err != nil {
		panic(err)
	}

	var bill Bill
	err = datastore.Get(c, key, &bill)
	if err == datastore.ErrNoSuchEntity {
		return
	}

	_, ukey := getUserBy(c, "Email", user.Current(c).Email)
	if !ukey.Equal(bill.Sender) {
		panic("You can't edit a bill that's not yours")
	}

	bill.Note = body["note"].(string)
	if _, err := datastore.Put(c, key, &bill); err != nil {
		panic(err)
    }
}

func updateName(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	body := parseJsonBody(r)

	user, ukey := getUserBy(c, "Email", user.Current(c).Email)

	user.Name = body["name"].(string)
	if _, err := datastore.Put(c, ukey, user); err != nil {
		panic(err)
    }
}

func buildPayment(c appengine.Context, previous *Bill, amount float32) map[string]interface{} {
	var sender User
	err := datastore.Get(c, previous.Sender, &sender)
	if err != nil {
		panic(err)
	}

	return map[string]interface{}{
		"Name":       sender.Name,
		"Email":      sender.Email,
		"Amount":     fmt.Sprintf("%.2f", amount),
	}
}

func findInBill(bill *Bill, key *datastore.Key) int {
	for i, v := range bill.Receivers {
		if v.Equal(key) {
			return i
		}
	}

	return -1
}

func getPaid(datePaid []time.Time) (all bool, res []bool) {
	res = make([]bool, len(datePaid))
	all = true
	for i, v := range datePaid {
		res[i] = v.After(time.Unix(0, 0))
		all = all && res[i]
	}
	return
}

func parseJsonBody(r *http.Request) map[string]interface{} {
	defer r.Body.Close()
	raw, err := ioutil.ReadAll(r.Body)
	if err != nil {
		panic(err)
	}

	body := make(map[string]interface{}, 0)
	if err := json.Unmarshal(raw, &body); err != nil {
		panic(err)
	}

	return body
}

func checkEmail(email string) bool {
	at := strings.Index(email, "@")
	dot := strings.Index(email, ".")

	return 0 < at && 0 < dot && at < dot
}
