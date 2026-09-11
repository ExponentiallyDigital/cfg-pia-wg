# bug_mailsend-go.md

- FIX: on stock sending a test email from the watchdog configure screen fails.

A TEAL entry was written to the app log (it should have been RED as it was an error) "Test email failed - see router log for derails", and no error was shown on the appp screen. There should have been a dismissable warning that the email could not be sent and instead of telling the user to look at the router log, the dismissable warning, which must now be implemented, should point the user to the app log, the app log should capture all error conditions from the send event. The watchdog did sucessfully deploy though. The router log contains this entry:

Sep  5 14:18:10 cfg-pia-wg: Email FAILED (exit=1) stderr=[2026/09/05 14:18:07 Detecting MIME Type....|2026/09/05 14:18:07 Number of attachments: 0|2026/09/05
14:18:07 Tag: string,required,N/A,-smtp|2026/09/05 14:18:07 args length: 4|2026/09/05 14:18:07 Tag: number,optional,587,1,65535,-port|2026/09/05 14:18:07 args
 length: 6|2026/09/05 14:18:07 Flag: -port|2026/09/05 14:18:07 in Numberic validator default: 587|2026/09/05 14:18:07 num: 465|2026/09/05 14:18:07 Tag: string
,optional,localhost,-domain|2026/
Sep  5 14:18:10 cfg-pia-wg: TCP diag: smtp.gmail.com:465 is UNREACHABLE - check host and port

See `scripts\mailsend-go_test.sh` for a working example I built and tested of how to send emails with mailsend-go.

FTR here are the complete mailsend-go command options:

./mailsend-go --help
 Version: @($) mailsend-go v1.0.12
 https://github.com/muquit/mailsend-go
 Compiled with go version: go1.26.3

 mailsend-go [options]
  Where the options are:
  -debug                 - Print debug messages
  -sub subject           - Subject
  -t to,to..*            - email address/es of the recipient/s. Required
  -list file             - file with list of email addresses.
                           Syntax is: Name, email_address
  -fname name            - name of sender
  -f address*            - email address of the sender. Required
  -cc cc,cc..            - carbon copy addresses
  -bcc bcc,bcc..         - blind carbon copy addresses
  -rt rt                 - reply to address
  -smtp host/IP          - hostname/IP address of the SMTP server. Required
                           unless '-use' is set.
  -use mailprovider      - Arranges -smtp, -port and -ssl for you when using
                           a well known mailprovider. Allowed values:
                           gmail, yahoo, outlook, gmx, zoho, aol
  -port port             - port of SMTP server. Default is 587
  -domain domain         - domain name for SMTP HELO. Default is localhost
  -info                  - Print info about SMTP server and exit
  -printCerts            - Print Certificates in connection with -info. Default is No
  -ssl                   - SMTP over SSL. Default is StartTLS
  -verifyCert            - Verify Certificate in connection. Default is No
  -ex                    - show examples
  -help                  - show this help
  -q                     - quiet
  -log filePath          - write log messages to this file
  -cs charset            - Character set for text/HTML. Default is utf-8
  -V                     - show version and exit
  auth                   - Auth Command
   -user username*       - For basic auth: username for ESMTP authentication
                           For OAuth2: email address of the authenticated account
                           Required for both auth methods
   -pass password*       - password for ESMTP authentication. Required for basic auth
   -oauth2               - Use OAuth2 XOAUTH2 authentication instead of basic auth
   -token access_token*  - OAuth2 access token. Required when -oauth2 is used
  body                   - body command for attachment for mail body
   -msg msg              - message to show as body
   -file path            - or path of a text/HTML file
   -mime-type type       - MIME type of the body content. Default is detected
  attach                 - attach command. Repeat for multiple attachments
   -file path*           - path of the attachment. Required
   -name name            - name of the attachment. Default is filename
   -mime-type type       - MIME-Type of the attachment. Default is detected
   -inline               - Set Content-Disposition to "inline".
                           Default is "attachment"
  header                 - Header Command. Repeat for multiple headers
   -name header          - Header name
   -value value          - Header value

The options with * are required.

NB as noted in `scripts\mailsend-go_test.sh`, do not use `info` as mailsend-go exits after info is printed, same for `-PrintCerts` - I have filed a feature request with the author to change that, ETA unknown.

FAILS -> ./mailsend-go -debug -ssl -verifyCert -printCerts -info...
WORKS -> ./mailsend-go -debug -ssl -verifyCert...

---
