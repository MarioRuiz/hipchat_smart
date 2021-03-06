#for the case of testing, just run this file adding in the end a call to rules with the parameters you want
if defined?(respond)
  @testing = false
else
  @testing = true
  @questions = Hash.new()

  def respond(message, jid_user)
    puts message
  end

  #context: previous message
  #to: user that should answer
  def ask(question, context, to, jid_user)
    puts "Bot: #{question}"
    @questions[to]=context
  end
end

# from: Full name of the person sending the message
# command: command to run
# processed: in case the command has been already processed on Bot class, by default false
# help: These are specific commands on this bot.
# help:     They will be accessible only when the bot is listening to you just writing the command
# help:     or the bot is not listening to you but requested on demand, for example:
# help:       !THE_COMMAND
# help:       @bot THE_COMMAND
# help:       @FIRST_NAME_BOT THE_COMMAND
# help:       FIRST_NAME_BOT THE_COMMAND
# help:
def rules(from, command, processed, jid_user)
  if @testing
    puts "#{from}: #{command}"
    if @questions.keys.include?(from)
      context = @questions[from]
      @questions[from] = command
      command = context
    end
  end
  firstname = from.split(" ").first
  case command

    # help: echo SOMETHING
    # help:     repeats SOMETHING
    # help:
    when /echo\s(.+)/i
      respond $1, jid_user

    # help: go to sleep
    # help:   it will sleep the bot for 10 seconds
    # help:
    when /go\sto\ssleep/i
      unless @questions.keys.include?(from)
        ask("do you want me to take a siesta?", command, from, jid_user)
      else
        case @questions[from]
          when /yes/i, /yep/i, /sure/i
            respond "zZzzzzzZZZZZZzzzzzzz!", jid_user
            respond "I'll be sleeping for 10 secs... just for you", jid_user
            sleep 10
          when /no/i, /nope/i, /cancel/i
            @questions.delete(from)
            respond "Thanks, I'm happy to be awake", jid_user
          else
            respond "I don't understand", jid_user
            ask("are you sure do you want me to sleep? (yes or no)", "go to sleep", from, jid_user)
        end
      end
    else
      unless processed
        resp = %w{ what huh sorry }.sample
        respond "#{firstname}: #{resp}?", jid_user
      end
  end
end


#for the case of testing just running this file, write the dialogue in here:
if @testing
  rules "Peter Johson", "go to sleep, you look tired", false
  rules "Peter Johson", "yes", false
end
