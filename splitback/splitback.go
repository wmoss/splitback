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
	EmailPrefix string
}

var config Config = Config{}
var env map[string]string

func init() {
	http.HandleFunc("/signup", signup)
	http.HandleFunc("/finduser", findUser)
	http.HandleFunc("/bill", bill)
	http.HandleFunc("/remove", remove)
	http.HandleFunc("/pay", pay)
	http.HandleFunc("/payed", payed)
	http.HandleFunc("/", main)

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

func requireLogin(c appengine.Context, w http.ResponseWriter, r *http.Request) bool {
	u := user.Current(c)
	if u == nil {
		url, err := user.LoginURL(c, r.URL.String())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return true
		}
		w.Header().Set("Location", url)
		w.WriteHeader(http.StatusFound)
		return true
	}
	return false
}

type User struct {
	Name  string
	Email string
}

func signup(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)
	if requireLogin(c, w, r) {
		return
	}

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

func main(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)
	if requireLogin(c, w, r) {
		return
	}

	user, _ := getUserBy(c, "Email", user.Current(c).Email)
	newUser := user == nil

	tc := map[string]interface{}{"New": newUser}
	if newUser {
		tc["Name"] = "New User"
	} else {
		tc["Name"] = user.Name
		tc["Owed"] = buildOwed(c)
		tc["Owe"] = buildOwe(c)
		tc["Bills"] = buildBills(c)
	}

	tmpl, _ := template.ParseFiles("templates/main.html", "templates/join.html")

	if err := tmpl.Execute(w, tc); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}

	return
}

func findUser(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	var users []User
	datastore.NewQuery("Users").GetAll(c, &users)

	names := make([]string, len(users))
	for i, u := range users {
		names[i] = u.Name
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

	defer r.Body.Close()
	raw, err := ioutil.ReadAll(r.Body)
	if err != nil {
		panic(err)
	}

	body := make(map[string]interface{}, 0)
	if err := json.Unmarshal(raw, &body); err != nil {
		panic(err)
	}
	recipients := body["recipients"].([]interface{})

	sender, sender_key := getUserBy(c, "Email", user.Current(c).Email)

	receivers := make([]*datastore.Key, 0)
	amounts := make([]float32, 0)
	paid := make([]time.Time, 0)
	for _, recipient := range recipients {
		recipient := recipient.(map[string]interface{})
		if recipient["name"] == "" {
			continue
		}

		user, key := getUserBy(c, "Name", recipient["name"].(string))
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
		Note: body["note"].(string),
	}

	if _, err := datastore.Put(c, datastore.NewIncompleteKey(c, "Bills", nil), &bill); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	fmt.Fprint(w, buildOwed(c))
}

func remove(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	key, err := datastore.DecodeKey(r.FormValue("key"))
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

	fmt.Fprint(w, buildOwed(c))
}

func pay(w http.ResponseWriter, r *http.Request) {
	c := appengine.NewContext(r)

	recipient, _ := datastore.DecodeKey(r.FormValue("Recipient"))
	amount, _ := strconv.ParseFloat(r.FormValue("Amount"), 32)

	_, sender := getUserBy(c, "Email", user.Current(c).Email)

	url := getPayUrl(c, sender, recipient, r.FormValue("Bills"), float32(amount))

	http.Redirect(w, r, url, http.StatusFound)
}

func payed(w http.ResponseWriter, r *http.Request) {
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

	http.Redirect(w, r, "/", http.StatusFound)
}

func buildOwed(c appengine.Context) string {
	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Sender =", key)

	out := bytes.NewBuffer(nil)
	tmpl, _ := template.ParseFiles("templates/bill-row.html")

	for t := q.Run(c); ; {
		var bill Bill
		key, err := t.Next(&bill)
		if err == datastore.Done {
			break
		}
		if err != nil {
			panic(err)
		}

		receivers := make([]*User, len(bill.Receivers))

		for i := range receivers {
			receivers[i] = new(User)
		}
		err = datastore.GetMulti(c, bill.Receivers, receivers)
		if err != nil {
			panic(err)
		}

		tc := map[string]interface{}{
			"Timestamp": bill.Timestamp.Format("Mon, Jan 02 2006 15:04:05 MST"),
			"Receivers": receivers,
			"Amounts":   bill.Amounts,
			"Paid":      getPaid(bill.DatePaid),
			"Key":       key.Encode(),
			"Note":  bill.Note,
		}
		if err := tmpl.Execute(out, tc); err != nil {
			panic(err)
		}
	}

	return out.String()
}

func buildOwe(c appengine.Context) string {
	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Receivers =", key)

	out := bytes.NewBuffer(nil)
	tmpl, _ := template.ParseFiles("templates/bill-row.html")

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
		tc := map[string]interface{}{
			"Timestamp": bill.Timestamp.Format("Mon, Jan 02 2006 15:04:05 MST"),
			"Receivers": []User{sender},
			"Amounts":   []float32{bill.Amounts[index]},
			"Paid":      getPaid([]time.Time{bill.DatePaid[index]}),
			"Note":  bill.Note,
		}
		if err := tmpl.Execute(out, tc); err != nil {
			panic(err)
		}
	}

	return out.String()
}

func buildPayRow(c appengine.Context, previous *Bill, amount float32, bills string, out *bytes.Buffer) {
	tmpl, err := template.ParseFiles("templates/pay-row.html")
	if err != nil {
		panic(err)
	}

	var sender User
	err = datastore.Get(c, previous.Sender, &sender)
	if err != nil {
		panic(err)
	}

	tc := map[string]interface{}{
		"Recipient": previous.Sender.Encode(),
		"Name":      sender.Name,
		"Amount":    fmt.Sprintf("%.2f", amount),
		"Bills":     bills,
	}
	if err := tmpl.Execute(out, tc); err != nil {
		panic(err)
	}
}

func buildBills(c appengine.Context) string {
	_, key := getUserBy(c, "Email", user.Current(c).Email)

	q := datastore.NewQuery("Bills").
		Filter("Receivers =", key).
		Order("Sender")

	out := bytes.NewBuffer(nil)

	previous := Bill{}
	amount := float32(0.0)
	bills := make([]string, 0)
	first := true
	weeklyAmount := float32(0.0)
	oneWeekAgo := time.Now().Add(-time.Hour * 24 * 7)
	for t := q.Run(c); ; {
		var bill Bill
		billKey, err := t.Next(&bill)
		if err == datastore.Done {
			if !first {
				buildPayRow(c, &previous, amount, strings.Join(bills, ","), out)
			}
			break
		}
		if err != nil {
			panic(err)
		}

		if bill.Sender.Equal(key) {
			if bill.Timestamp.After(oneWeekAgo) {
				for i, v := range bill.DatePaid {
					if v.After(time.Unix(0, 0)) && !bill.Receivers[i].Equal(key) {
						weeklyAmount += bill.Amounts[i]
					}
				}
			}
			continue
		}

		index := findInBill(&bill, key)

		if datePaid := bill.DatePaid[index]; datePaid.After(time.Unix(0, 0)) {
			if datePaid.After(oneWeekAgo) {
				weeklyAmount += bill.Amounts[index]
			}
			continue
		}

		if weeklyAmount > 250 {
			break
		}

		if bill.Sender.Equal(previous.Sender) || first {
			amount += bill.Amounts[index]
			bills = append(bills, billKey.Encode())
		} else {
			buildPayRow(c, &previous, amount, strings.Join(bills, ","), out)
			amount = bill.Amounts[index]
			bills = []string{billKey.Encode()}
		}

		first = false
		previous = bill
	}

	//Paypal requires we limit to 250 sent or received per week
	if weeklyAmount > 250 {
		raw, err := ioutil.ReadFile("templates/over-limit.html")
		if err != nil {
			panic(err)
		}
		return string(raw)
	}

	return out.String()
}

func findInBill(bill *Bill, key *datastore.Key) int {
	for i, v := range bill.Receivers {
		if v.Equal(key) {
			return i
		}
	}

	return -1
}

func getPaid(datePaid []time.Time) []bool {
	res := make([]bool, len(datePaid))
	for i, v := range datePaid {
		res[i] = v.After(time.Unix(0, 0))
	}
	return res
}
