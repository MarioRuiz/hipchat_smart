Gem::Specification.new do |s|
  s.name        = 'hipchat_smart'
  s.version     = '1.1.0'
  s.date        = '2018-04-09'
  s.summary     = "Create a hipchat bot that is smart and so easy to expand, create new bots on demand, run ruby code on chat, create shortcuts..."
  s.description = "Create a hipchat bot that is smart and so easy to expand, create new bots on demand, run ruby code on chat, create shortcuts... 
  The main scope of this gem is to be used internally in the company so teams can create team rooms with their own bot to help them on their daily work, almost everything is suitable to be automated!! 
  hipchat_smart can create bots on demand, create shortcuts, run ruby code... just on a chat room. 
  You can access it just from your mobile phone if you want and run those tests you forgot to run, get the results, restart a server... no limits."
  s.authors     = ["Mario Ruiz"]
  s.email       = 'marioruizs@gmail.com'
  s.files       = ["lib/hipchat_smart.rb","lib/hipchat_smart_rules.rb","LICENSE","README.md"]
  s.extra_rdoc_files = ["LICENSE","README.md"]
  s.homepage    = 'https://github.com/MarioRuiz/hipchat_smart'
  s.license       = 'MIT'
  s.add_runtime_dependency 'xmpp4r', '~> 0.5', '>= 0.5.6'
  s.add_runtime_dependency 'hipchat', '~> 1.6', '>= 1.6.0'
  s.required_ruby_version = '>= 2.4'
end