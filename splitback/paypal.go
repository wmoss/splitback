package splitback

import (
	"appengine"
	"appengine/datastore"
	"appengine/urlfetch"
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"text/template"
)

const payTmpl = `{
  "actionType":"PAY",
  "currencyCode":"USD",
  "receiverList":{"receiver":[{
      "amount":"{{.Amount}}",
      "email":"{{.EmailPrefix}}{{.RecipientEmail}}"}]
  },

  "returnUrl":"{{.AppUrl}}/payed?Sender={{.Sender}}&Bills={{.Bills}}",

  "cancelUrl": "{{.AppUrl}}/?payfailed",
  "requestEnvelope":{
    "errorLanguage":"en_US",
    "detailLevel":"ReturnAll"
  }
}`

func getPayUrl(c appengine.Context, sender *datastore.Key, recipient *datastore.Key, bills string, amount float32) string {
	var user User
	err := datastore.Get(c, recipient, &user)

	tmpl, err := template.New("pay").Parse(payTmpl)
	if err != nil {
		panic(err)
	}

	tc := map[string]interface{}{
		"Sender":         sender.Encode(),
		"Bills":          bills,
		"RecipientEmail": user.Email,
		"Amount":         fmt.Sprintf("%.2f", amount),
		"AppUrl":         config.AppUrl,
		"EmailPrefix":    config.EmailPrefix,
	}
	var data bytes.Buffer
	tmpl.Execute(&data, tc)

	req, err := http.NewRequest("POST", config.PayKeyUrl, &data)

	req.Header.Add("X-PAYPAL-SECURITY-USERID", config.User)
	req.Header.Add("X-PAYPAL-SECURITY-PASSWORD", config.Password)
	req.Header.Add("X-PAYPAL-SECURITY-SIGNATURE", config.Signature)
	req.Header.Add("X-PAYPAL-REQUEST-DATA-FORMAT", "JSON")
	req.Header.Add("X-PAYPAL-RESPONSE-DATA-FORMAT", "JSON")
	req.Header.Add("X-PAYPAL-APPLICATION-ID", config.AppId)

	client := urlfetch.Client(c)
	resp, err := client.Do(req)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)

	res_ := make(map[string]interface{})
	json.Unmarshal(body, &res_)

	res := res_["responseEnvelope"].(map[string]interface{})

	if res["ack"].(string) != "Success" {
		c.Warningf("Paypal Failure: %v", res_)
		panic("Failure")
	}

	return "https://www.paypal.com/webscr?cmd=_ap-payment&paykey=" + res_["payKey"].(string)
}
