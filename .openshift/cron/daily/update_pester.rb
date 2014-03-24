#!/bin/env ruby
# return cards that haven't been updated in 5 days so your lazy ass can give an
# update :D

require 'trello'
require 'mongo'
require_relative '../../../utils'

include Trello
include Trello::Authorization
include Mongo

Trello::Authorization.const_set :AuthPolicy, OAuthPolicy
OAuthPolicy.consumer_credential = OAuthCredential.new ENV['TRELLO_API_KEY'], ENV['TRELLO_API_SECRET']
OAuthPolicy.token = OAuthCredential.new ENV['TRELLO_API_ACCESS_TOKEN_KEY'], nil

BACK_FIVE = Time.now - 432000 # 432000 seconds == 5 days

board = Trello::Board.find(ENV['TRELLO_BOARD_ID'])
watched_lists = ENV.keys.collect { |k| Trello::List.find(ENV[k]) if k =~ /TRELLO_LONELY_LIST_.*/ }.delete_if{ |k| k.nil? }

# get a list of all cards that need to be updated
MongoClient.new(ENV['OPENSHIFT_MONGODB_DB_HOST'], ENV['OPENSHIFT_MONGODB_DB_PORT']).db(ENV['OPENSHIFT_APP_NAME']) do |db|
  db.authenticate(ENV['OPENSHIFT_MONGODB_DB_USERNAME'], ENV['OPENSHIFT_MONGODB_DB_PASSWORD'])

  board.members.each do |member|
    lonely_cards = member.cards.each.collect do |card|
      if watched_lists.include?(card.list) and not card.closed and card.last_activity_date > BACK_FIVE
        recent_comment = false

        comments = card.actions({:filter => :commentCard})
        comments.each do |comment|
          recent_comment = true if comment.date > BACK_FIVE
          break if recent_comment
        end

        card unless recent_comment
      end
    end
    lonely_cards.delete_if { |c| c.nil? }

    cards_ids_urls = lonely_cards.each.collect { |c| {'card_id' => c.id, 'card_url' => c.url} }

    # dump the card IDs and URLs into the database
    doc = db[$login_collection].find_one({'login' => member.username})

    unless doc.nil?
      doc['lonely_cards'] = cards_ids_urls
      db[$login_collection].update({'_id' => doc['_id']}, doc)
    end
  end
end
