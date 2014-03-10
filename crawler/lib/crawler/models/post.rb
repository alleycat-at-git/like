require_relative "fetchable"
require_relative "mapping"

module Crawler
  module Models
    class Post < ActiveRecord::Base
      extend Fetchable
      fetcher :wall_get, :owner_id, Mapping.post

      validates_uniqueness_of :vk_id, scope: :owner_id

      belongs_to :user_profile, primary_key: "vk_id", foreign_key: "owner_id"
      has_many :likes
      has_many :likes_user_profiles, through: :likes, source: "user_profile"

      def self.load_or_fetch(id)
        fetched = Post.fetch(id)
        existing = Post.where(owner_id: id).to_a
        existing_ids = existing.map(&:vk_id)
        fetched.delete_if do |model|
          existing_ids.include? model.vk_id
        end
        fetched.each do |model|
          model.save
        end
        fetched + existing
      end

      def fetch_likes
        user_ids=Like.fetch([vk_id, owner_id]).map(&:user_profile_id)
        users = UserProfile.load_or_fetch(user_ids)
        users = UserProfile.mass_insert(users)
        Like.mass_insert(users.map(&:id), self.id)
        users
      end
    end
  end
end