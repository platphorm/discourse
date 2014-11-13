# Be sure to restart your server when you modify this file.

# PH_CUSTOMIZATIONS: Ensure DC and NF expire session cookies after the same length of time
# to prevent the DC login from lasting longer than NF (if the user just leaves the browser)
Discourse::Application.config.session_store :cookie_store, {key: '_forum_session', expire_after: 120.minutes}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rails generate session_migration")
# Discourse::Application.config.session_store :active_record_store
