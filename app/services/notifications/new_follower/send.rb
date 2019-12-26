# send notifications about the new followers
module Notifications
  module NewFollower
    class Send
      # @param follow_data [Hash]
      #   * :followable_id [Integer]
      #   * :followable_type [String] - "User" or "Organization"
      #   * :follower_id [Integer] - user id
      def initialize(follow_data, is_read = false)
        follow_data = follow_data.is_a?(FollowData) ? follow_data : FollowData.new(follow_data)
        @followable_id = follow_data.followable_id # fetch(:followable_id)
        @followable_type = follow_data.followable_type # fetch(:followable_type)
        @follower_id = follow_data.follower_id # fetch(:follower_id)
        @is_read = is_read
      end

      delegate :user_data, to: Notifications

      def self.call(*args)
        new(*args).call
      end

      def call
        # All recent Follows having the specified followable id and type.
        recent_follows_of_followable_id_and_type = Follow.where(followable_type: followable_type, followable_id: followable_id).
          where("created_at > ?", 24.hours.ago).order("created_at DESC")

        notification_params = build_notification_params_from_followable

        # Move the empty result handling higher up in the method.
        # (If followers was empty, recent_follows would need to be too, right?)
        # When is this called? Is it only called in response to a new follow, and if so, would recent_follows ever be empty?
        if recent_follows_of_followable_id_and_type.empty?

          # In these notification params, we specify only the followed, not the follower.
          # Is this correct? Is there only one Notification instance per followed?
          # If so, then we would be deleting a notification triggered by a different follower, right? Is this ok?
          notification = Notification.find_by(notification_params)&.destroy
        else
          notification = Notification.find_or_initialize_by(notification_params)

          # Previous implementation changed by @rhymes in PR #5236 to next code line
          # notification.notifiable_id = recent_follows.first.id

          # This line will set the notifiable to the follower id if it occurs in the followers, or nil if not.
          # If not, would we even be here? Is it possible for this to be called if not?
          # Could we not instead just do: notification.notifiable_id = @follower_id?
          # (Also, do we want '@follower_id' here, or just use the attr_reader `follower_id` instead?)
          notification.notifiable_id = recent_follows_of_followable_id_and_type.detect { |f| f.follower_id == @follower_id }&.id

          notification.notifiable_type = "Follow"
          notification.json_data = create_json_data(recent_follows_of_followable_id_and_type)
          notification.notified_at = Time.current
          notification.read = is_read
          notification.save!
        end
        notification
      end

      private

      attr_reader :followable_id, :followable_type, :follower_id, :is_read

      def follower
        User.find(follower_id)
      end

      def build_notification_params_from_followable
        params = { action: "Follow" }
        if followable_type == "User"
          params[:user_id] = followable_id
        elsif followable_type == "Organization"
          params[:organization_id] = followable_id
        end
        params
      end

      def create_json_data(recent_follows_of_followable_id_and_type)
        # All Users corresponding to the above Follows
        followers = User.where(id: recent_follows_of_followable_id_and_type.select(:follower_id))

        # This block-local variable shadows the instance method by the same name. Change it?
        # follower_hashes = followers.map { |follower| user_data(follower) }
        follower_hashes = followers.map { |f| user_data(f) }

        # follower_hashes will include all followers, including the user in question, is that right and ok?
        # (Should this follower be included in the aggregated_siblings?)
        { user: user_data(follower), aggregated_siblings: follower_hashes }
      end
    end
  end
end
