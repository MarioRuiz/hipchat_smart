# HipChat Smart

[![Gem Version](https://badge.fury.io/rb/hipchat_smart.svg)](https://rubygems.org/gems/hipchat_smart)

Create a hipchat bot that is really smart and so easy to expand.

The main scope of this ruby gem is to be used internally in your company so teams can create team rooms with their own bot to help them on their daily work, almost everything is suitable to be automated!!

hipchat_smart can create bots on demand, create shortcuts, run ruby code... just on a chat room, you can access it just from your mobile phone if you want and run those tests you forgot to run, get the results, restart a server... no limits.

## Installation and configuration

    $ gem install hipchat_smart
    
After you install it you will need just a couple of things to configure it.

Create a file like this on the folder you want:

```ruby
#jid of the room that will act like the master room, main room
MASTER_ROOM="1_my_master_room"
#names of the master users
MASTER_USERS=["Mario Ruiz Sanchez"]

require 'hipchat_smart'

settings = {
    jid: 'bot_user_jid@your_company_hipchat_domain.com/bot',
    nick: 'bot user name',
    password: "xxxxxxxxxxxx",
    token: 'xxxxxxxxxxxxxxxxxxxxxxx',
}

Bot.new(settings).listen.always
```

To enable XMPP/Jabber on your Hipchat and be able to get the jids you need, go to: https://hipchat.yourCompanyDomain.com/account/xmpp

The MASTER_ROOM will be the room where you will be able to create other bots and will have special treatment.

The MASTER_USERS will have full access to everything. The names should be written exactly the same like they appear on hipchat.

I recommend to create an specific user on hipchat to be the bot so less risks.

Add the jid for that user specifying the hipchat domain in your company and finishing with /bot

For the token remember you need to generate a token on the hipchat app for the bot user.
To generate the token go to: https://hipchat.yourCompanyDomain.com/account/api

## Usage

### creating the MASTER BOT
Let's guess the file you created was called my_smart_bot.rb so, just run it:
```
ruby my_smart_bot.rb
```

After the run, it will be generated a rules file with the same name but adding _rules, in this example: my_smart_bot_rules.rb

The rules file can be edited and will be only affecting this particular bot.

You can add all the rules you want for your bot in the rules file, this is an example:

```ruby
def rules(from, command, processed)
  firstname = from.split(" ").first
  case command

    # help: echo SOMETHING
    # help:     repeats SOMETHING
    # help:
    when /echo\s(.+)/i
      respond $1

    # help: go to sleep
    # help:   it will sleep the bot for 10 seconds
    # help:
    when /go\sto\ssleep/i
      unless @questions.keys.include?(from)
        ask("do you want me to take a siesta?", command, from)
      else
        case @questions[from]
          when /yes/i, /yep/i, /sure/i
            respond "zZzzzzzZZZZZZzzzzzzz!"
            respond "I'll be sleeping for 10 secs... just for you"
            sleep 10
          when /no/i, /nope/i, /cancel/i
            @questions.delete(from)
            respond "Thanks, I'm happy to be awake"
          else
            respond "I don't understand"
            ask("are you sure do you want me to sleep? (yes or no)", "go to sleep", from)
        end
      end
    else
      unless processed
        resp = %w{ what huh sorry }.sample
        respond "#{firstname}: #{resp}?"
      end
  end
end

```
### How to access the bot
You can access the bot directly on the MASTER ROOM, on a secondary room where the bot is running and directly by opening a private chat with the bot, in this case the conversation will be just between you and the bot.

### Available commands even when the bot is not listening to you
Some of the commands are available always even when the bot is not listening to you but it is running

**_`bot help`_**

**_`bot what can I do?`_**

>It will display all the commands we can use
>What is displayed by this command is what is written on your rules file like this: #help: THE TEXT TO SHOW

**_`Hello Bot`_**

**_`Hello THE_FIRSTNAME_OF_THE_BOT`_**

>Also apart of Hello you can use Hallo, Hi, Hola, What's up, Hey, Zdravo, Molim, Hæ

>Bot starts listening to you

**_`Bye Bot`_**

**_`Bye THE_FIRST_NAME_OF_THE_BOT`_**

>Also apart of Bye you can use Bæ, Good Bye, Adiós, Ciao, Bless, Bless Bless, Zbogom, Adeu

>Bot stops listening to you

**_`exit bot`_**

**_`quit bot`_**

**_`close bot`_**

>The bot stops running and also stops all the bots created from this master room

>You can use this command only if you are an admin user and you are on the master room

**_`start bot`_**

**_`start this bot`_**

>The bot will start to listen

>You can use this command only if you are an admin user

**_`pause bot`_**

**_`pause this bot`_**

>The bot will pause so it will listen only to admin commands

>You can use this command only if you are an admin user

**_`bot status`_**
   
>Displays the status of the bot

>If on master room and admin user also it will display info about bots created

**_`create bot on ROOM_NAME`_**

>Creates a new bot on the room specified. 

>hipchat_smart will create a default rules file specific for your room. 
You can edit it and add the rules you want. 
As soon as you save the file after editing it will become available on your room.

>It will work only if you are on Master room

**_`kill bot on ROOM_NAME`_**

>Kills the bot on the specified room

>Only works if you are on Master room and you created that bot or you are an admin user

### Available commands only when listening to you or on demand

All the commands described on here or on your specific Rules file can be used when the bot is listening to you or on demand.

For the bot to start listening to you you need to use the "Hi bot" command or one of the aliases

Also you can call any of these commands on demand by using:

**_`!THE_COMMAND`_**

**_`@bot THE_COMMAND`_**

**_`@FIRST_NAME_BOT THE_COMMAND`_**

**_`FIRST_NAME_BOT THE_COMMAND`_**

Apart of the specific commands you define on the rules file of the room, you can use:

**_`ruby RUBY_CODE`_**

**_`/code RUBY_CODE`_**

>runs the code supplied and returns the output. Examples:

>ruby require 'json'; res=[]; 20.times {res<<rand(100)}; my_json={result: res}; puts my_json.to_json

>/code puts (34344/99)*(34+14)


**_`add shortcut NAME: COMMAND`_**

**_`add shortcut for all NAME: COMMAND`_**

**_`shortchut NAME: COMMAND`_**

**_`shortchut for all NAME: COMMAND`_**

>It will add a shortcut that will execute the command we supply.

>In case we supply 'for all' then the shorcut will be available for everybody

>Example:
>add shortcut for all Spanish account: /code require 'iso/iban'; 10.times {puts ISO::IBAN.random('ES')}

>Then to call this shortcut:

>/sc spanish account

>/shortcut Spanish Account

**_`delete shortcut NAME`_**

>It will delete the shortcut with the supplied name

**_`see shortcuts`_**

>It will display the shortcuts stored for the user and for :all

**_`jid room ROOM_NAME`_**
>shows the jid of a room name


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marioruiz/hipchat_smart.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

