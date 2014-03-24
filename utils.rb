require 'mongo'
require 'trello'

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

# return an authenticated connection to the openshift mongo db
def db_connect
  db = MongoClient.new(ENV['OPENSHIFT_MONGODB_DB_HOST'], ENV['OPENSHIFT_MONGODB_DB_PORT']).db(ENV['OPENSHIFT_APP_NAME'])
  db.authenticate(ENV['OPENSHIFT_MONGODB_DB_USERNAME'], ENV['OPENSHIFT_MONGODB_DB_PASSWORD'])
  return db
end

# store a nick/login pair in the db
def store_login(nick, login)
  db = db_connect
  # TODO: check to see if login is already stored. if so, update instead of insert
  # TODO: close db connection after this is done!
  db[$login_collection].insert({'_id' => nick, 'login' => login})
end

# given a nick, grab the stored trello login from the db
def get_login(nick)
  # TODO: close db connection after this is done!
  db = db_connect
  doc = db[$login_collection].find_one({'_id' => nick_parse(nick)})
  doc[$login_collection] if doc
end

# check the db to see if the listed members have lonely cards that need updating
def pester(members)
end
