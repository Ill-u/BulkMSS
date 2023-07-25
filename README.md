# BulkMSS - Bulk Email Sender Script

![GitHub](https://img.shields.io/github/license/your_username/bulk-email-sender) 
![GitHub last commit](https://img.shields.io/github/last-commit/Ill-u/bulkSSM)

## Description

This is a Ruby script for sending bulk emails using multiple SMTP servers and multithreading. The script allows you to specify SMTP server details, email recipients, sender name, email subject, and email message from external files. The emails will be sent to recipients in bulk, using the provided SMTP servers and managing failures efficiently to maximize successful deliveries.

## Features

- Send bulk emails using multiple SMTP servers and threads
- Retry sending emails to failed recipients with different SMTP servers
- Gracefully handle errors and log the email sending process

## Requirements

- Ruby (tested with Ruby 2.6.0 or higher)
- Required Ruby Gems: `net/smtp`, `timeout`, `logger`, `colorize`, `optparse`, `concurrent`, and `set`

## Usage

1. Clone this repository or download the `bulkMSS.rb` script.

2. Create the following input files:

   - `smtps.txt`: A text file containing SMTP server details in the format `smtp|port|username|password`. Each line represents a different SMTP server.
   - `recipients.txt`: A text file containing a list of email recipients, with each email address on a separate line.
   - `sender_name.txt`: A text file containing the sender's name (e.g., Your Company Name or Your Name).
   - `subject.txt`: A text file containing the subject of the email.
   - `message.txt`: A text file containing the email message.

3. Make sure your SMTP servers support the specified port (e.g., 587 for TLS/STARTTLS).

4. Run the script with the following command:

   ```bash
   ruby bulkMSS.rb -s smtps.txt -r recipients.txt -n sender_name.txt -b subject.txt -m message.txt -c 10 -t 5
