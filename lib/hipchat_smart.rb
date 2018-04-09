require 'xmpp4r'
require 'xmpp4r/muc/helper/simplemucclient'
require 'xmpp4r/muc/helper/mucbrowser'
require 'xmpp4r/roster'
require 'hipchat'
require 'open-uri'
require 'cgi'
require 'json'
require 'logger'
require 'fileutils'
require 'open3'

if ARGV.size==0
  ROOM = MASTER_ROOM
  ON_MASTER_ROOM = true
  ADMIN_USERS = MASTER_USERS
  RULES_FILE = "#{$0.gsub('.rb', '_rules.rb')}" unless defined?(RULES_FILE)
  unless File.exist?(RULES_FILE)
    default_rules=(__FILE__).gsub(".rb", "_rules.rb")
    FileUtils.copy_file(default_rules, RULES_FILE)
  end
  STATUS_INIT = :on
else
  ON_MASTER_ROOM = false
  ROOM = ARGV[0]
  ADMIN_USERS=ARGV[1].split(",")
  RULES_FILE=ARGV[2]
  STATUS_INIT = ARGV[3].to_sym
end

SHORTCUTS_FILE = "hipchat_smart_shortcuts_#{ROOM}.rb".gsub(" ", "_")

class Bot

  attr_accessor :config, :client, :muc, :muc_browser, :roster

  def initialize(config)
    Dir.mkdir("./logs") unless Dir.exist?("./logs")
    Dir.mkdir("./shortcuts") unless Dir.exist?("./shortcuts")
    logfile=File.basename(RULES_FILE.gsub("_rules_", "_logs_"), ".rb")+".log"
    @logger = Logger.new("./logs/#{logfile}")
    config_log=config.dup
    config_log.delete(:password)
    @logger.info "Initializing bot: #{config_log.inspect}"

    #XMPP namespace for Hipchat Server by default, if not supplied with room
    config[:room] = ROOM
    if config[:room].include?("@")
      @xmpp_namespace = config[:room].scan(/.+@(.+)/).join
    else
      @xmpp_namespace = "conf.btf.hipchat.com"
    end

    config[:room]=config[:room]+"@"+@xmpp_namespace

    self.config = config
    self.client = Jabber::Client.new(config[:jid])
    self.muc = Jabber::MUC::SimpleMUCClient.new(client)
    self.muc_browser = Jabber::MUC::MUCBrowser.new(client)

    if Jabber.logger = config[:debug]
      Jabber.debug = true
    end

    @listening = Array.new

    @bots_created=Hash.new()
    @shortcuts=Hash.new()
    @shortcuts[:all]=Hash.new()

    if File.exist?("./shortcuts/#{SHORTCUTS_FILE}")
      file_sc = IO.readlines("./shortcuts/#{SHORTCUTS_FILE}").join
      unless file_sc.to_s() == ""
        @shortcuts = eval(file_sc)
      end
    end

    if ON_MASTER_ROOM and File.exist?($0.gsub(".rb", "_bots.rb"))
      file_conf = IO.readlines($0.gsub(".rb", "_bots.rb")).join
      unless file_conf.to_s() == ""
        @bots_created = eval(file_conf)
        if @bots_created.kind_of?(Hash)
          @bots_created.each {|key, value|
            @logger.info "ruby #{$0} \"#{value[:jid].gsub(/@.+/, '')}\" \"#{value[:admins]}\" \"#{value[:rules_file]}\" #{value[:status]}"
            t = Thread.new do
              `ruby #{$0} \"#{value[:jid].gsub(/@.+/, '')}\" \"#{value[:admins]}\" \"#{value[:rules_file]}\" #{value[:status]}`
            end
            value[:thread]=t
          }
        end
      end
    end

    client.connect
    client.auth(config[:password])
    client.on_exception do |exc, jab, where|
      @logger.fatal "CLIENT EXCEPTION on #{where}: #{exc}"
      sleep 10
      #todo: reconnect
    end
    config.delete(:password)
    client.send(Jabber::Presence.new.set_type(:available))

    self.roster = Jabber::Roster::Helper.new(client)

    @status = STATUS_INIT
    @questions = Hash.new()
    @rooms_jid=Hash.new()
    @rooms_name=Hash.new()
    self
  end

  def update_bots_file
    file = File.open($0.gsub(".rb", "_bots.rb"), 'w')
    bots_created=@bots_created.dup
    bots_created.each {|k, v| v[:thread]=""}
    file.write bots_created.inspect
    file.close
  end

  def update_shortcuts_file
    file = File.open("./shortcuts/#{SHORTCUTS_FILE}", 'w')
    file.write @shortcuts.inspect
    file.close
  end

  def get_rooms_name_and_jid
    @rooms_jid=Hash.new()
    @rooms_name=Hash.new()
    muc_browser.muc_rooms(@xmpp_namespace).each {|jid, name|
      jid=jid.to_s.gsub("@#{@xmpp_namespace}", "")
      @rooms_jid[name]=jid
      @rooms_name[jid]=name
    }
  end


  def listen
    @salutations = [config[:nick].split(/\s+/).first, "bot"]

    muc.on_message do |time, nick, text|
      jid_user = nil
      res = process_first(time, nick, text, jid_user)
      next if res.to_s=="next"
    end

    muc.join(config[:room] + '/' + config[:nick])
    respond "Bot started"

    #accept subscriptions from everyone
    roster.add_subscription_request_callback do |item, pres|
      roster.accept_subscription(pres.from)
    end

    if ON_MASTER_ROOM
		client.add_message_callback do |m|
		  unless m.body.to_s==""
			jid_user=m.from.node+"@"+m.from.domain
			user=roster[jid_user]
			unless user.nil?
			  res = process_first("", user.attributes["name"], m.body, jid_user)
			  next if res.to_s=="next"
			end
		  end
		end
	end

    @logger.info "Bot listening"
    self
  end

  def process_first(time, nick, text, jid_user)
    if nick==config[:nick] or nick==(config[:nick] + " · Bot") #if message is coming from the bot
      begin
        @logger.info "#{nick}: #{text}"
        case text
          when /^Bot has been killed by/
            exit!
          when /^Changed status on (.+) to :(.+)/i
            room=$1
            status=$2
            @bots_created[room][:status]=status.to_sym
            update_bots_file()
        end
        return :next #don't continue analyzing
      rescue Exception => stack
        @logger.fatal stack
        return :next
      end

    end

    if text.match?(/^\/(shortcut|sc)\s(.+)/i)
      shortcut=text.scan(/\/\w+\s*(.+)\s*/i).join.downcase
      if @shortcuts.keys.include?(nick) and @shortcuts[nick].keys.include?(shortcut)
        text=@shortcuts[nick][shortcut]
      elsif @shortcuts.keys.include?(:all) and @shortcuts[:all].keys.include?(shortcut)
        text=@shortcuts[:all][shortcut]
      else
        respond "Shortcut not found", jid_user
        return :next
      end

    end

    if @questions.keys.include?(nick)
      command=@questions[nick]
      @questions[nick]=text
    else
      command=text
    end

    begin
      t = Thread.new do
        begin
          processed = process(nick, command, jid_user)
          @logger.info "command: #{nick}> #{command}" if processed
          if @status==:on and
              ((@questions.keys.include?(nick) or
                  @listening.include?(nick) or
                  command.match?(/^@?#{@salutations.join("|")}:*\s+(.+)$/i) or
                  command.match?(/^!(.+)$/)))
            @logger.info "command: #{nick}> #{command}" unless processed
            begin
              eval(File.new(RULES_FILE).read) if File.exist?(RULES_FILE)
            rescue Exception => stack
              @logger.fatal "ERROR ON RULES FILE: #{RULES_FILE}"
              @logger.fatal stack
            end
            if defined?(rules)
              command[0]="" if command[0]=="!"
              command.gsub!(/^@\w+:*\s*/, "")
              rules(nick, command, processed, jid_user)
            else
              @logger.warn "It seems like rules method is not defined"
            end
          end
        rescue Exception => stack
          @logger.fatal stack
        end

      end

    rescue => e
      @logger.error "exception: #{e.inspect}"
    end
  end

  #help: Commands you can use:
  #help:
  def process(from, command, jid_user)
    firstname = from.split(/ /).first
    processed=true

    case command

      #help: Hello Bot
      #help: Hello THE_FIRSTNAME_OF_THE_BOT.
      #help: Also apart of Hello you can use Hallo, Hi, Hola, What's up, Hey, Zdravo, Molim, Hæ
      #help:    Bot starts listening to you
      #help:
      when /^(Hello|Hallo|Hi|Hola|What's\sup|Hey|Zdravo|Molim|Hæ)\s(#{@salutations.join("|")})\s*$/i
        if @status==:on
          greetings=['Hello', 'Hallo', 'Hi', 'Hola', "What's up", "Hey", "Zdravo", "Molim", "Hæ"].sample
          respond "#{greetings} #{firstname}", jid_user
          @listening<<from unless @listening.include?(from)
        end

      #help: Bye Bot
      #help: Bye THE_FIRST_NAME_OF_THE_BOT
      #help: Also apart of Bye you can use Bæ, Good Bye, Adiós, Ciao, Bless, Bless Bless, Zbogom, Adeu
      #help:    Bot stops listening to you
      #help:
      when /^(Bye|Bæ|Good\sBye|Adiós|Ciao|Bless|Bless\sBless|Zbogom|Adeu)\s(#{@salutations.join("|")})\s*$/i
        if @status==:on
          bye=['Bye', 'Bæ', 'Good Bye', 'Adiós', "Ciao", "Bless", "Bless bless", "Zbogom", "Adeu"].sample
          respond "#{bye} #{firstname}", jid_user
          @listening.delete(from)
        end

      #help: exit bot
      #help: quit bot
      #help: close bot
      #help:    The bot stops running and also stops all the bots created from this master room
      #help:    You can use this command only if you are an admin user and you are on the master room
      #help:
      when /^exit\sbot/i, /^quit\sbot/i, /^close\sbot/i
        if ON_MASTER_ROOM
          if ADMIN_USERS.include?(from) #admin user
            unless @questions.keys.include?(from)
              ask("are you sure?", command, from, jid_user)
            else
              case @questions[from]
                when /yes/i, /yep/i, /sure/i
                  respond "Game over!", jid_user
                  respond "Ciao #{firstname}!", jid_user
                  @bots_created.each {|key, value|
                    value[:thread]=""
                    send_msg_room(key, "Bot has been killed by #{from}")
                    sleep 0.5
                  }
                  update_bots_file()
                  sleep 0.5
                  exit!
                when /no/i, /nope/i, /cancel/i
                  @questions.delete(from)
                  respond "Thanks, I'm happy to be alive", jid_user
                else
                  respond "I don't understand", jid_user
                  ask("are you sure do you want me to close? (yes or no)", "quit bot", from, jid_user)
              end
            end
          else
            respond "Only admin users can kill me", jid_user
          end

        else
          respond "To do this you need to be an admin user in the master room", jid_user
        end

      #help: start bot
      #help: start this bot
      #help:    the bot will start to listen
      #help:    You can use this command only if you are an admin user
      #help:
      when /^start\s(this\s)?bot$/i
        if ADMIN_USERS.include?(from) #admin user
          respond "This bot is running and listening from now on. You can pause again: pause this bot", jid_user
          @status=:on
          unless ON_MASTER_ROOM
            get_rooms_name_and_jid() unless @rooms_name.keys.include?(MASTER_ROOM) and @rooms_name.keys.include?(ROOM)
            send_msg_room @rooms_name[MASTER_ROOM], "Changed status on #{@rooms_name[ROOM]} to :on"
          end
        else
          respond "Only admin users can change my status", jid_user
        end


      #help: pause bot
      #help: pause this bot
      #help:    the bot will pause so it will listen only to admin commands
      #help:    You can use this command only if you are an admin user
      #help:
      when /^pause\s(this\s)?bot$/i
        if ADMIN_USERS.include?(from) #admin user
          respond "This bot is paused from now on. You can start it again: start this bot", jid_user
          respond "zZzzzzZzzzzZZZZZZzzzzzzzz", jid_user
          @status=:paused
          unless ON_MASTER_ROOM
            get_rooms_name_and_jid() unless @rooms_name.keys.include?(MASTER_ROOM) and @rooms_name.keys.include?(ROOM)
            send_msg_room @rooms_name[MASTER_ROOM], "Changed status on #{@rooms_name[ROOM]} to :paused"
          end
        else
          respond "Only admin users can put me on pause", jid_user
        end


      #help: bot status
      #help:    Displays the status of the bot
      #help:    If on master room and admin user also it will display info about bots created
      #help:
      when /^bot\sstatus/i
        respond "Status: #{@status}. Rules file: #{File.basename RULES_FILE} ", jid_user
        if @status==:on
          respond "I'm listening to [#{@listening.join(", ")}]", jid_user
          if ON_MASTER_ROOM and ADMIN_USERS.include?(from)
            @bots_created.each {|key, value|
              respond "#{key}: #{value}", jid_user
            }
          end
        end

      #help: create bot on ROOM_NAME
      #help:    creates a new bot on the room specified
      #help:    it will work only if you are on Master room
      #help:
      when /^create\sbot\son\s(.+)\s*/i
        if ON_MASTER_ROOM
          room=$1
          if @bots_created.keys.include?(room)
            respond "There is already a bot in this room: #{room}, kill it before", jid_user
          else
            rooms=Hash.new()
            muc_browser.muc_rooms(@xmpp_namespace).each {|jid, name|
              rooms[name]=jid
            }
            if rooms.keys.include?(room)
              jid=rooms[room]
              @rooms_jid[room]=jid
              if jid!=config[:room]
                jid=jid.to_s.gsub(/@.+/, '')
                begin
                  rules_file="hipchat_smart_rules_#{jid}_#{from.gsub(" ", "_")}.rb"
                  if defined?(RULES_FOLDER)
                    rules_file=RULES_FOLDER+rules_file
                  else
                    Dir.mkdir("rules") unless Dir.exist?("rules")
                    Dir.mkdir("rules/#{jid}") unless Dir.exist?("rules/#{jid}")
                    rules_file="./rules/#{jid}/" + rules_file
                  end
                  default_rules=(__FILE__).gsub(".rb", "_rules.rb")
                  File.delete(rules_file) if File.exist?(rules_file)
                  FileUtils.copy_file(default_rules, rules_file) unless File.exist?(rules_file)
                  admin_users=Array.new()
                  admin_users=[from]+MASTER_USERS
                  admin_users.uniq!
                  @logger.info "ruby #{$0} \"#{jid}\" \"#{admin_users.join(",")}\" \"#{rules_file}\" :on"
                  t = Thread.new do
                    `ruby #{$0} \"#{jid}\" \"#{admin_users.join(",")}\" \"#{rules_file}\" :on`
                  end
                  @bots_created[room]={
                      creator_name: from,
                      jid: jid,
                      status: :on,
                      created: Time.now.strftime('%Y-%m-%dT%H:%M:%S.000Z')[0..18],
                      rules_file: rules_file,
                      admins: admin_users.join(","),
                      thread: t
                  }
                  respond "The bot has been created on room: #{room}. Rules file: #{File.basename rules_file}", jid_user
                  update_bots_file()
                rescue Exception => stack
                  @logger.fatal stack
                  message="Problem creating the bot on room #{room}. Error: <#{stack}>."
                  @logger.error message
                  respond message, jid_user
                end
              else
                respond "There is already a bot in this room: #{room}, and it is the Master Room!", jid_user
              end

            else
              respond "There is no room with that name: #{room}, please be sure is written exactly the same", jid_user
            end
          end
        else
          respond "Sorry I cannot create bots from this room, please visit the master room", jid_user
        end

      #help: kill bot on ROOM_NAME
      #help:    kills the bot on the specified room
      #help:    Only works if you are on Master room and you created that bot or you are an admin user
      #help:
      when /^kill\sbot\son\s(.+)\s*/i
        if ON_MASTER_ROOM
          room=$1
          if @bots_created.keys.include?(room)
            if @bots_created[room][:admins].split(",").include?(from)
              if @bots_created[room][:thread].kind_of?(Thread) and @bots_created[room][:thread].alive?
                @bots_created[room][:thread].kill
              end
              @bots_created.delete(room)
              update_bots_file()
              respond "Bot on room: #{room}, has been killed and deleted.", jid_user
              send_msg_room(room, "Bot has been killed by #{from}")
            else
              respond "You need to be the creator or an admin of that room", jid_user
            end
          else
            respond "There is no bot in this room: #{room}", jid_user
          end
        else
          respond "Sorry I cannot kill bots from this room, please visit the master room", jid_user
        end

      #help: bot help
      #help: bot what can I do?
      #help:    it will display this help
      #help:
      when /^bot help/i, /^bot,? what can I do/i
        help_message = IO.readlines(__FILE__).join
        help_message_rules = IO.readlines(RULES_FILE).join
        respond "/quote " + help_message.scan(/#\s*help\s*:(.*)/).join("\n"), jid_user
        respond "/quote " + help_message_rules.scan(/#\s*help\s*:(.*)/).join("\n"), jid_user

      else
        processed = false
    end

    #only when :on and (listening or on demand)
    if @status==:on and
        ((@questions.keys.include?(from) or
            @listening.include?(from) or
            command.match?(/^@?#{@salutations.join("|")}:*\s+(.+)$/i) or
            command.match?(/^!(.+)$/)))
      processed2=true

      # help:
      # help: These commands will run only when bot is listening to you or on demand, for example:
      # help:       !THE_COMMAND
      # help:       @bot THE_COMMAND
      # help:       @FIRST_NAME_BOT THE_COMMAND
      # help:       FIRST_NAME_BOT THE_COMMAND.
      # help:
      case command

        #help: add shortcut NAME: COMMAND
        #help: add shortcut for all NAME: COMMAND
        #help: shortchut NAME: COMMAND
        #help: shortchut for all NAME: COMMAND
        #help:    It will add a shortcut that will execute the command we supply.
        #help:    In case we supply 'for all' then the shorcut will be available for everybody
        #help:    Example:
        #help:        add shortcut for all Spanish account: /code require 'iso/iban'; 10.times {puts ISO::IBAN.random('ES')}
        #help:    Then to call this shortcut:
        #help:        /sc spanish account
        #help:        /shortcut Spanish Account
        #help:
        when /(add\s)?shortcut\s(for\sall)?\s*(.+):\s(.+)/i
          for_all=$2
          shortcut_name=$3.to_s.downcase
          command_to_run=$4
          @shortcuts[from]=Hash.new() unless @shortcuts.keys.include?(from)

          if !ADMIN_USERS.include?(from) and @shortcuts[:all].include?(shortcut_name) and !@shortcuts[from].include?(shortcut_name)
            respond "Only the creator of the shortcut or an admin user can modify it", jid_user
          elsif !@shortcuts[from].include?(shortcut_name)
            #new shortcut
            @shortcuts[from][shortcut_name]=command_to_run
            @shortcuts[:all][shortcut_name]=command_to_run if for_all.to_s!=""
            update_shortcuts_file()
            respond "shortcut added", jid_user
          else

            #are you sure? to avoid overwriting existing
            unless @questions.keys.include?(from)
              ask("The shortcut already exists, are you sure you want to overwrite it?", command, from, jid_user)
            else
              case @questions[from]
                when /^(yes|yep)/i
                  @shortcuts[from][shortcut_name]=command_to_run
                  @shortcuts[:all][shortcut_name]=command_to_run if for_all.to_s!=""
                  update_shortcuts_file()
                  respond "shortcut added", jid_user
                  @questions.delete(from)
                when /^no/i
                  respond "ok, I won't add it", jid_user
                  @questions.delete(from)
                else
                  respond "I don't understand, yes or no?", jid_user
              end
            end

          end

        #help: delete shortcut NAME
        #help:    It will delete the shortcut with the supplied name
        #help:
        when /delete\sshortcut\s(.+)/i
          shortcut=$1.to_s.downcase
          deleted=false

          if !ADMIN_USERS.include?(from) and @shortcuts[:all].include?(shortcut) and !@shortcuts[from].include?(shortcut)
            respond "Only the creator of the shortcut or an admin user can delete it", jid_user
          elsif (@shortcuts.keys.include?(from) and @shortcuts[from].keys.include?(shortcut)) or
              (ADMIN_USERS.include?(from) and @shortcuts[:all].include?(shortcut))
            #are you sure? to avoid deleting by mistake
            unless @questions.keys.include?(from)
              ask("are you sure you want to delete it?", command, from, jid_user)
            else
              case @questions[from]
                when /^(yes|yep)/i
                  respond "shortcut deleted!", jid_user
                  respond "#{shortcut}: #{@shortcuts[from][shortcut]}", jid_user
                  @shortcuts[from].delete(shortcut)
                  @shortcuts[:all].delete(shortcut)
                  @questions.delete(from)
                  update_shortcuts_file()
                when /^no/i
                  respond "ok, I won't delete it", jid_user
                  @questions.delete(from)
                else
                  respond "I don't understand, yes or no?", jid_user
              end
            end
          else
            respond "shortcut not found", jid_user
          end

        #help: see shortcuts
        #help:    It will display the shortcuts stored for the user and for :all
        #help:
        when /see\sshortcuts/i
          msg=""
          if @shortcuts[:all].keys.size>0
            msg="Available shortcuts for all:\n"
            @shortcuts[:all].each {|name, value|
              msg+="#{name}: #{value}\n"
            }
            respond msg, jid_user
          end

          if @shortcuts.keys.include?(from) and @shortcuts[from].keys.size>0
            new_hash=@shortcuts[from].dup
            @shortcuts[:all].keys.each {|k| new_hash.delete(k)}
            if new_hash.keys.size>0
              msg="Available shortcuts for #{from}:\n"
              new_hash.each {|name, value|
                msg+="#{name}: #{value}\n"
              }
              respond msg, jid_user
            end
          end
          respond "No shortcuts found", jid_user if msg==""

        #help: jid room ROOM_NAME
        #help:    shows the jid of a room name
        #help:
        when /jid room (.+)/
          room_name=$1
          get_rooms_name_and_jid()
          if @rooms_jid.keys.include?(room_name)
            respond "the jid of #{room_name} is #{@rooms_jid[room_name]}", jid_user
          else
            respond "room: #{room_name} not found", jid_user
          end

        # help: ruby RUBY_CODE
        # help: /code RUBY_CODE
        # help:     runs the code supplied and returns the output. Examples:
        # help:       ruby require 'json'; res=[]; 20.times {res<<rand(100)}; my_json={result: res}; puts my_json.to_json
        # help:       /code puts (34344/99)*(34+14)
        # help:
        when /ruby\s(.+)/im, /\/code\s(.+)/im
          code=$1
          code.gsub!("\\n", "\n")
          unless code.match?(/System/i) or code.match?(/Kernel/i) or code.include?("File") or
              code.include?("`") or code.include?("exec") or code.include?("spawn") or code.include?("IO") or
              code.match?(/open3/i) or code.match?(/bundle/i) or code.match?(/gemfile/i) or code.include?("%x") or
              code.include?("ENV")
            begin
              stdout, stderr, status = Open3.capture3("ruby -e \"#{code.gsub('"', '\"')}\"")
              if stderr==""
                if stdout==""
                  respond "Nothing returned. Remember you need to use p or puts to print", jid_user
                else
                  respond stdout, jid_user
                end
              else
                respond stderr, jid_user
              end
            rescue Exception => exc
              respond exc, jid_user
            end
          else
            respond "Sorry I cannot run this due security issues", jid_user
          end

        else
          processed2=false
      end
      processed=true if processed or processed2
    end

    return processed
  end

  def respond(msg,jid_user=nil)
    if jid_user.nil?
      muc.send Jabber::Message.new(muc.room, msg)
    else #private message
      send_msg_user(jid_user, msg)
    end
  end

  #context: previous message
  #to: user that should answer
  def ask(question, context, to, jid_user=nil)
    if jid_user.nil?
      muc.send Jabber::Message.new(muc.room, "#{to}: #{question}")
    else #private message
      send_msg_user(jid_user, "#{to}: #{question}")
    end
    @questions[to]=context
  end


  # Uses the hipchat gem (REST)
  # to: (String) Room name
  # msg: (String) message to send
  def send_msg_room(to, msg)
    unless msg==""
      hc_client=HipChat::Client.new(config[:token], :server_url => config[:jid].to_s.scan(/.+@(.+)\/.+/).join)
      hc_client[to].send("Bot", msg)
    end
  end

  #to send messages without listening for a response to users
  #to: jid
  def send_msg_user(to, msg)
    unless msg==""
      to=to+"@chat."+@xmpp_namespace.scan(/\w+\.(.+)/).join unless to.include?("@")
      message = Jabber::Message::new(to, msg)
      message.type=:chat
      client.send message
    end
  end

  def always
    loop {sleep 1}
  end

  private :update_bots_file, :get_rooms_name_and_jid, :update_shortcuts_file
end

