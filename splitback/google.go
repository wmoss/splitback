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
	"Content-type: text/html\r\n" +
	"X-Bills-Paid: %s\r\n\r\n" +
	"Payment from Splitback\r\n\r\n"

func sendSquareCashEmail(client *http.Client, from string, payment *PaymentOwed) {
	gmailService, err := gmail.New(client)
	if err != nil {
		panic(err)
	}

	to := fmt.Sprintf("%s <%s>", payment.Sender.Name, payment.Sender.Email)
	raw := fmt.Sprintf(emailTemplate, from, to, payment.Amount, strings.Join(payment.Bills, ","))

	msg := &gmail.Message{Raw: base64.URLEncoding.EncodeToString([]byte(raw))}

	msg, err = gmailService.Users.Messages.Send("me", msg).Do()
	if err != nil {
		panic(err)
	}
}
