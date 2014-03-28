require 'mongo'
require 'trello'

include Mongo

$login_collection = 'users'

# parse an irc nick into its base format
# eg: nick_parse('achvatal|away') => 'achvatal'
def nick_parse(nick)
  match = /([a-zA-Z\d]+)/.match(nick)
  shortnick = ''

  if match
    shortnick = match[1]
  else
    shortnick = nick
  end

  return shortnick
end

# return a list of registered nicks
def registered_nicks
  nicks = db_connect do |db|
    db[$login_collection].find({}, {fields: ['_id']}).to_a
  end

  nicks.collect { |n| n['_id'] }
end

# given a registered login, find a user's current nick
def nick_find(login)
  shortnick = db_connect do |db|
    doc = db[$login_collection].find_one({login: login})
    doc['_id'] if doc
  end

  nick = Channel(ENV['TRELLO_BOT_CHANNEL']).users.collect do |user, mode|
    user.nick if shortnick == nick_parse(user.nick)
  end
  nick.delete_if { |n| n.nil? }

  nick[0]
end

# provide an authenticated connection to the openshift mongo db
def db_connect(&block)
  con = MongoClient.new(ENV['OPENSHIFT_MONGODB_DB_HOST'], ENV['OPENSHIFT_MONGODB_DB_PORT'])
  db = con.db(ENV['OPENSHIFT_APP_NAME'])
  db.authenticate(ENV['OPENSHIFT_MONGODB_DB_USERNAME'], ENV['OPENSHIFT_MONGODB_DB_PASSWORD'])
  if block
    result = yield db
    con.close
    result
  else
    db
  end
end

# store a nick/login pair in the db
def register(nick, login, token)
  db_connect do |db|
    db[$login_collection].update({'_id' => nick}, {'_id' => nick, 'login' => login, 'token' => token, 'lonely_cards' => [], 'pestered_today' => false}, {:upsert => true})
  end
end

# given a nick, grab the stored trello login from the db
def get_login(nick)
  db_connect do |db|
    doc = db[$login_collection].find_one({_id: nick_parse(nick)})
    doc['login'] if doc
  end
end

# given a nick, grab the lonely cards from the db
def lonely_cards(nick)
  db_connect do |db|
    doc = db[$login_collection].find_one({_id: nick_parse(nick)})
    doc['lonely_cards'] if doc
  end
end
