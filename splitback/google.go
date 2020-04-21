package splitback

import (
	"appengine"
	"appengine/urlfetch"
	"code.google.com/p/goauth2/oauth"
	"encoding/base64"
	"fmt"
	gmail "google.golang.org/api/gmail/v1"
	"net/http"
	"strings"
	"time"
	"strconv"
)

var oauthConfig = &oauth.Config{
	ClientId:     "109196545149-togdpo2jspqh81l5rb6qqk67g7l8h9uj.apps.googleusercontent.com",
	ClientSecret: "KdaK_GKRcBsUSP_43ugRP0e9",
	RedirectURL:  "http://localhost:8080/rest/oauth2callback",
	Scope:        "https://www.googleapis.com/auth/gmail.modify",
	AuthURL:      "https://accounts.google.com/o/oauth2/auth",
	TokenURL:     "https://accounts.google.com/o/oauth2/token",
}

func requestOAuthRedirectUrl() string {
	return oauthConfig.AuthCodeURL("")
}

func getTransport(c appengine.Context) *oauth.Transport {
	return &oauth.Transport{
		Config: oauthConfig,
		Transport: &urlfetch.Transport{
			Context:                       c,
			Deadline:                      time.Minute,
			AllowInvalidServerCertificate: true,
		},
	}
}

func exchangeCode(c appengine.Context, code string) *oauth.Token {
	transport := getTransport(c)

	token, err := transport.Exchange(code)
	if err != nil {
		panic(err)
	}
	return token
}

func getAuthedClient(c appengine.Context, token *oauth.Token) *http.Client {
	transport := getTransport(c)
	transport.Token = token

	return transport.Client()
}

const emailTemplate = "" +
	"From: %s\r\n" +
	"To: %s\r\n" +
	"Subject: $%.2f\r\n" +
	"X-Bills-Paid: %s\r\n\r\n" +
	"Payment from Splitback for:\n" +
	"%s\r\n\r\n"

func sendSquareCashEmail(client *http.Client, from string, payment *PaymentOwed) {
	gmailService, err := gmail.New(client)
	if err != nil {
		panic(err)
	}

	to := fmt.Sprintf("%s <%s>", payment.Sender.Name, payment.Sender.Email)
	billKeys := strings.Join(payment.BillKeysEncoded, ",")
	billText := ""
	for _, bill := range payment.Bills {
		billText += fmt.Sprintf("%s: %s\n", bill.Note, strconv.FormatFloat(bill.Amount, 'f', 2, 32))
	}
	raw := fmt.Sprintf(emailTemplate, from, to, payment.Amount, billKeys, billText)

	msg := &gmail.Message{Raw: base64.URLEncoding.EncodeToString([]byte(raw))}

	msg, err = gmailService.Users.Messages.Send("me", msg).Do()
	if err != nil {
		panic(err)
	}
}

func checkSquareCashEmails(c appengine.Context, client *http.Client, date string) {
	gmailService, err := gmail.New(client)
	if err != nil {
		panic(err)
	}

	c.Infof("Fetching messages for %s", date)
	query := fmt.Sprintf("label:inbox after:%s", date)
	result, err := gmailService.Users.Messages.List("me").Q(query).Do()
	if err != nil {
		panic(err) // log.Fatalf("Unable to retrieve messages: %v", err)
	}

	c.Infof("Found %d messages", len(result.Messages))

	for _, m := range result.Messages {
		msg, err := gmailService.Users.Messages.Get("me", m.Id).Do()
		if err != nil {
			panic(err) // log.Fatalf("Unable to retrieve message %v: %v", m.Id, err)
		}

		c.Infof("Found message")

		for _, h := range msg.Payload.Headers {
			if h.Name == "X-Bills-Paid" {
				c.Infof("%s", h.Value)
				c.Infof("%s", msg.LabelIds)
			}
		}
	}
}
