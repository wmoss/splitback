package splitback

import (
	"appengine"
	"appengine/datastore"
	"appengine/urlfetch"
	"bytes"
	"encoding/json"
	"io/ioutil"
	"net/http"
	"strings"
	"text/template"
)

const payTmplString = `{
  "actionType":"PAY",
  "currencyCode":"USD",
  "receiverList":{"receiver":[{{.Receivers}}]},

  "returnUrl":"{{.AppUrl}}/rest/paySucceeded",
  "ipnNotificationUrl":"{{.AppUrl}}/rest/payIpn?Sender={{.Sender}}&Bills={{.Bills}}",
  "cancelUrl": "{{.AppUrl}}/rest/payFailed",

  "requestEnvelope":{
    "errorLanguage":"en_US",
    "detailLevel":"ReturnAll"
  }
}`

const receiverTmplString = `{
      "amount":"{{.Amount}}",
      "email":"{{.EmailPrefix}}{{.RecipientEmail}}",
      "paymentType":"PERSONAL"
    }`

func getPayKey(c appengine.Context, sender *datastore.Key, recipients []map[string]interface{}, bills []string) string {
	payTmpl, err := template.New("pay").Parse(payTmplString)
	if err != nil {
		panic(err)
	}

	receiverTmpl, err := template.New("receiver").Parse(receiverTmplString)
	if err != nil {
		panic(err)
	}

	receivers := make([]string, len(recipients))
	for i, recipient := range recipients {
		out := bytes.NewBuffer(nil)

		tc := map[string]interface{}{
			"RecipientEmail": recipient["Email"].(string),
			"Amount":         recipient["Amount"].(string),
			"EmailPrefix":    config.EmailPrefix,
		}
		if err := receiverTmpl.Execute(out, tc); err != nil {
			panic(err)
		}

		receivers[i] = out.String()
	}

	tc := map[string]interface{}{
		"Sender":    sender.Encode(),
		"Bills":     strings.Join(bills, ","),
		"AppUrl":    config.AppUrl,
		"Receivers": strings.Join(receivers, ","),
	}
	var data bytes.Buffer
	payTmpl.Execute(&data, tc)

	req, err := http.NewRequest("POST", config.PayKeyUrl, &data)
	if err != nil {
		panic(err)
	}

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

	return res_["payKey"].(string)
}
