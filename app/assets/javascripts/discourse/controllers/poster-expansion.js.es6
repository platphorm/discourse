import ObjectController from 'discourse/controllers/object';

export default ObjectController.extend({
  needs: ['topic'],
  visible: false,
  user: null,
  name: null, // PH_CUSTOMIZATION: Show both username and name in poster expansion
  username: null,
  participant: null,
  avatar: null,

  postStream: Em.computed.alias('controllers.topic.postStream'),
  enoughPostsForFiltering: Em.computed.gte('participant.post_count', 2),

  showFilter: Em.computed.and('postStream.hasNoFilters', 'enoughPostsForFiltering'),
  showName: Discourse.computed.propertyNotEqual('user.name', 'user.username'),

  hasUserFilters: Em.computed.gt('postStream.userFilters.length', 0),

  showBadges: Discourse.computed.setting('enable_badges'),

  moreBadgesCount: function() {
    return this.get('user.badge_count') - this.get('user.featured_user_badges.length');
  }.property('user.badge_count', 'user.featured_user_badges.@each'),

  showMoreBadges: Em.computed.gt('moreBadgesCount', 0),

  // PH_CUSTOMIZATION: Show both username and name in poster expansion
  show: function(name, username, uploadedAvatarId) {
    // XSS protection (should be encapsulated)
    username = username.replace(/[^A-Za-z0-9_]/g, "");
    var url = "/users/" + username;

    // Don't show on mobile
    if (Discourse.Mobile.mobileView) {
      Discourse.URL.routeTo(url);
      return;
    }

    var currentUsername = this.get('username'),
        wasVisible = this.get('visible');

    if (uploadedAvatarId) {
      // PH_CUSTOMIZATION: Show both username and name in poster expansion
      this.set('avatar', {name: 'ZUNZ_name', username: username, uploaded_avatar_id: uploadedAvatarId});
    } else {
      this.set('avatar', null);
    }

    // PH_CUSTOMIZATION: Show both username and name in poster expansion
    this.setProperties({visible: true, name: name, username: username});

    // If we click the avatar again, close it.
    if (username === currentUsername && wasVisible) {
      // PH_CUSTOMIZATION: Show both username and name in poster expansion
      this.setProperties({ visible: false, name: null, username: null, avatar: null });
      return;
    }

    this.set('participant', null);

    // Retrieve their participants info
    var participants = this.get('topic.details.participants');
    if (participants) {
      this.set('participant', participants.findBy('username', username));
    }

    var self = this;
    self.set('user', null);
    Discourse.User.findByUsername(username).then(function (user) {
      self.set('user', user);
      self.set('avatar', user);
    });
  },

  close: function() {
    this.set('visible', false);
  },

  actions: {
    togglePosts: function(user) {
      var postStream = this.get('controllers.topic.postStream');
      postStream.toggleParticipant(user.get('username'));
      this.close();
    },

    cancelFilter: function() {
      var postStream = this.get('postStream');
      postStream.cancelFilter();
      postStream.refresh();
      this.close();
    }
  }

});


