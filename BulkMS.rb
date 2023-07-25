require 'net/smtp'
require 'timeout'
require 'logger'
require 'colorize'
require 'optparse'
require 'concurrent'
require 'set'

# Set the encoding to UTF-8 for console output
$stdout.set_encoding('UTF-8')
$stderr.set_encoding('UTF-8')

# Initialize sets to store suspended SMTP servers and failed recipients for each server
@suspended_servers = Set.new
@failed_recipients = Hash.new { |h, k| h[k] = [] }

# Method to send an email using SMTP
def send_email(smtp_address, smtp_port, username, password, recipient, sender_name, subject, message)
  return false if @suspended_servers.include?(smtp_address) # Skip suspended SMTP servers

  success = false

  smtp = Net::SMTP.new(smtp_address, smtp_port)
  smtp.enable_starttls_auto if smtp_port == 587

  begin
    Timeout.timeout(60) do # Set a timeout for the connection
      smtp.start(smtp_address, username, password, :plain) do |smtp|
        smtp.open_message_stream(username, recipient) do |f|
          f.puts "From: #{sender_name} <#{username}>"
          f.puts "To: #{recipient}"
          f.puts "Subject: #{subject}"
          f.puts "MIME-Version: 1.0"
          f.puts "Content-Type: text/html; charset=UTF-8"
          f.puts
          f.puts message.force_encoding('UTF-8') # Encode message content correctly
        end
        puts "Sent email to #{recipient} by #{smtp_address}".colorize(:green)
        success = true
      end
    end

    # Check if any errors occurred during the email sending process
    unless success
      @suspended_servers << smtp_address # Add suspended SMTP server to the set
      puts "Skipping SMTP server #{smtp_address}: Unknown error occurred".colorize(:red)
    end

  rescue Net::SMTPAuthenticationError => e
    # Handle authentication error
    @suspended_servers << smtp_address # Add suspended SMTP server to the set
    puts "Skipping SMTP server #{smtp_address}: Authentication failed".colorize(:red)

  rescue Net::ReadTimeout
    # Handle read timeout error
    @suspended_servers << smtp_address # Add suspended SMTP server to the set
    puts "Skipping SMTP server #{smtp_address}: Read timeout occurred".colorize(:red)

  rescue Net::SMTPServerBusy, Net::SMTPUnknownError, Net::SMTPFatalError => e
    # Handle server-related errors
    error_message = e.message.gsub(/^[0-9]{3}\s/, '') # Remove the status code from the error message

    @suspended_servers << smtp_address # Add suspended SMTP server to the set
    puts "Skipping SMTP server #{smtp_address}: #{error_message}".colorize(:red)

  rescue => e
    # Handle other exceptions
    @suspended_servers << smtp_address # Add suspended SMTP server to the set
    puts "Skipping SMTP server #{smtp_address}: #{e.message}".colorize(:red)
  end

  success # Return whether the email was successfully sent
end

# Load SMTP server details from the file
def load_smtps(filename)
  smtps = []

  begin
    File.open(filename, 'r') do |file|
      file.each_line do |line|
        smtp, port, username, password = line.strip.split('|')
        smtps << { smtp: smtp, port: port.to_i, username: username, password: password }
      end
    end
  rescue Errno::ENOENT
    puts "SMTPs file not found: #{filename}".colorize(:red)
    exit
  end

  smtps
end

# Load email recipients from the file
def load_recipients(filename)
  recipients = []

  begin
    File.open(filename, 'r') do |file|
      file.each_line do |line|
        recipients << line.strip
      end
    end
  rescue Errno::ENOENT
    puts "Recipients file not found: #{filename}".colorize(:red)
    exit
  end

  recipients
end

# Load sender name from the file
def load_sender_name(filename)
  begin
    File.read(filename).strip
  rescue Errno::ENOENT
    puts "Sender name file not found: #{filename}".colorize(:red)
    exit
  end
end

# Load email subject from the file
def load_subject(filename)
  begin
    File.read(filename).strip
  rescue Errno::ENOENT
    puts "Subject file not found: #{filename}".colorize(:red)
    exit
  end
end

# Load email message from the file
def load_message(filename)
  begin
    File.read(filename).strip
  rescue Errno::ENOENT
    puts "Message file not found: #{filename}".colorize(:red)
    exit
  end
end

# Method to send bulk emails using thread pools
def send_bulk_emails(smtps_file, recipients_file, sender_name_file, subject_file, message_file, messages_per_server, num_threads)
  # Load SMTP server details
  smtps = load_smtps(smtps_file)
  total_smtp_count = smtps.length

  # Load email recipients
  recipients = load_recipients(recipients_file)
  total_recipient_count = recipients.length

  # Load sender name, subject, and message
  sender_name = load_sender_name(sender_name_file)
  subject = load_subject(subject_file)
  message = load_message(message_file)

  # Create a logger
  logger = Logger.new(STDOUT)
  logger.level = Logger::INFO

  total_sent = 0          # Initialize the total number of sent emails
  success_count = 0       # Initialize the count of successfully sent emails

  smtp_index = 0          # Index to track the current SMTP server to use

  while success_count < total_recipient_count
    current_smtp = smtps[smtp_index]

    # Create a thread pool for the current SMTP server
    thread_pool = Concurrent::FixedThreadPool.new(num_threads)

    # Submit tasks to the thread pool for the current SMTP server
    messages_per_server.times do
      break if success_count >= total_recipient_count   # Exit if all recipients have been successfully sent emails

      recipient = recipients.shift   # Retrieve the next recipient

      # Submit a task to the thread pool
      thread_pool.post do
        if send_email(current_smtp[:smtp], current_smtp[:port], current_smtp[:username], current_smtp[:password], recipient, sender_name, subject, message)
          success_count += 1
        else
          recipients << recipient   # Add the recipient back to the end of the list to be retried later
        end
      end

      total_sent += 1   # Increment the total number of sent emails
    end

    # Wait for all tasks for the current SMTP server to complete before moving to the next one
    thread_pool.shutdown
    thread_pool.wait_for_termination

    # Move to the next SMTP server in the loop
    smtp_index = (smtp_index + 1) % total_smtp_count
  end

  puts "Total sent emails: #{success_count} out of #{total_sent}".colorize(:green)
end





# Parse command-line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby bulk_email_sender.rb [options]"

  opts.on("-s", "--smtps FILE", "File containing SMTP server details") do |file|
    options[:smtps_file] = file
  end

  opts.on("-r", "--recipients FILE", "File containing email recipients") do |file|
    options[:recipients_file] = file
  end

  opts.on("-n", "--name FILE", "File containing sender name") do |file|
    options[:sender_name_file] = file
  end

  opts.on("-b", "--subject FILE", "File containing email subject") do |file|
    options[:subject_file] = file
  end

  opts.on("-m", "--message FILE", "File containing email message") do |file|
    options[:message_file] = file
  end

  opts.on("-c", "--count NUMBER", Integer, "Number of emails to send per SMTP server") do |count|
    options[:messages_per_server] = count
  end

  opts.on("-t", "--threads NUMBER", Integer, "Number of threads to use for sending emails") do |threads|
    options[:num_threads] = threads
  end
end.parse!

# Check if all required options are provided
if options[:smtps_file].nil? || options[:recipients_file].nil? || options[:sender_name_file].nil? || options[:subject_file].nil? || options[:message_file].nil? || options[:messages_per_server].nil? || options[:num_threads].nil?
  puts "Missing required options. Use -h or --help for usage instructions.".colorize(:red)
  exit
end

# Send bulk emails
send_bulk_emails(
  options[:smtps_file],
  options[:recipients_file],
  options[:sender_name_file],
  options[:subject_file],
  options[:message_file],
  options[:messages_per_server],
  options[:num_threads]
)


