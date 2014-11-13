require_dependency 'rate_limiter'

class SessionController < ApplicationController

  skip_before_filter :redirect_to_login_if_required

  skip_before_filter :check_xhr, only: ['sso', 'sso_login']

  def csrf
    render json: {csrf: form_authenticity_token }
  end

  def sso
    if SiteSetting.enable_sso
      redirect_to DiscourseSingleSignOn.generate_url(params[:return_path] || '/')
    else
      render nothing: true, status: 404
    end
  end

  def sso_login
    unless SiteSetting.enable_sso
      render nothing: true, status: 404
      return
    end

    sso = DiscourseSingleSignOn.parse(request.query_string)
    if !sso.nonce_valid?
      render text: "Timeout expired, please try logging in again.", status: 500
      return
    end

    return_path = sso.return_path
    sso.expire_nonce!

    if user = sso.lookup_or_create_user
      if SiteSetting.must_approve_users? && !user.approved?
        # TODO: need an awaiting approval message here
      else
        log_on_user user
      end
      redirect_to return_path
    else
      render text: "unable to log on user", status: 500
    end
  end

  def create

    unless allow_local_auth?
      render nothing: true, status: 500
      return
    end

    RateLimiter.new(nil, "login-hr-#{request.remote_ip}", 30, 1.hour).performed!
    RateLimiter.new(nil, "login-min-#{request.remote_ip}", 6, 1.minute).performed!

    params.require(:login)
    params.require(:password)

    return invalid_credentials if params[:password].length > User.max_password_length

    login = params[:login].strip
    login = login[1..-1] if login[0] == "@"

    if user = User.find_by_username_or_email(login)

      # If their password is correct
      unless user.confirm_password?(params[:password])
        invalid_credentials
        return
      end

      # If the site requires user approval and the user is not approved yet
      if login_not_approved_for?(user)
        login_not_approved
        return
      end

      # User signed on with username and password, so let's prevent the invite link
      # from being used to log in (if one exists).
      Invite.invalidate_for_email(user.email)
    else
      invalid_credentials
      return
    end

    if user.suspended?
      failed_to_login(user)
      return
    end

    (user.active && user.email_confirmed?) ? login(user) : not_activated(user)
  end

  def forgot_password
    params.require(:login)

    unless allow_local_auth?
      render nothing: true, status: 500
      return
    end

    RateLimiter.new(nil, "forgot-password-hr-#{request.remote_ip}", 6, 1.hour).performed!
    RateLimiter.new(nil, "forgot-password-min-#{request.remote_ip}", 3, 1.minute).performed!

    user = User.find_by_username_or_email(params[:login])
    if user.present?
      email_token = user.email_tokens.create(email: user.email)
      Jobs.enqueue(:user_email, type: :forgot_password, user_id: user.id, email_token: email_token.token)
    end
    # always render of so we don't leak information
    render json: {result: "ok"}

  rescue RateLimiter::LimitExceeded
    render_json_error(I18n.t("rate_limiter.slow_down"))
  end

  def current
    if current_user.present?
      render_serialized(current_user, CurrentUserSerializer)
    else
      render nothing: true, status: 404
    end
  end

  def destroy
    reset_session
    log_off_user
    render nothing: true
  end

  private

  def allow_local_auth?
    !SiteSetting.enable_sso && SiteSetting.enable_local_logins
  end

  def login_not_approved_for?(user)
    SiteSetting.must_approve_users? && !user.approved? && !user.admin?
  end

  def invalid_credentials
    render json: {error: I18n.t("login.incorrect_username_email_or_password")}
  end

  def login_not_approved
    render json: {error: I18n.t("login.not_approved")}
  end

  def not_activated(user)
    render json: {
      error: I18n.t("login.not_activated"),
      reason: 'not_activated',
      sent_to_email: user.find_email || user.email,
      current_email: user.email
    }
  end

  def failed_to_login(user)
    message = user.suspend_reason ? "login.suspended_with_reason" : "login.suspended"

    render json: { error: I18n.t(message, { date: I18n.l(user.suspended_till, format: :date_only),
                                            reason: user.suspend_reason}) }
  end

  def login(user)
    log_on_user(user)
    render_serialized(user, UserSerializer)
  end

end

# PH_CUSTOMIZATION: Collect all of the PH SessionController customizations here
# Consider putting them in the plugin
class SessionController < ApplicationController

  # PH_CUSTOMIZATION: The xhr? check does not seem reliable when issued from NF logouts
  # This is some ajax peculiarity, so add 'destroy' here
  skip_before_filter :check_xhr, only: ['sso', 'sso_login', 'destroy']

  # PH_CUSTOMIZATION: Disable the CSRF check for the preflight on destroy
  skip_before_filter :verify_authenticity_token, only: :destroy
  before_filter :verify_authenticity_token_on_destroy, only: :destroy

  # PH_CUSTOMIZATION: Get CORS working for session destruction (on logout in NF)
  # See http://www.tsheffler.com/blog/?p=428
  before_filter :cors_preflight_check, only: :destroy
  after_filter :cors_set_access_control_headers, only: :destroy

  private

  # PH_CUSTOMIZATION: Set CORS access control headers for preflights
  # If this is a preflight OPTIONS request, then short-circuit the
  # request, return only the necessary headers and return an empty
  # text/plain.
  def cors_preflight_check
    if request.method.to_s.downcase == 'options'
      headers['Access-Control-Allow-Origin'] = '*'
      headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
      headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-Prototype-Version, X-CSRF-Token'
      headers['Access-Control-Max-Age'] = '1728000'
      render :text => '', :content_type => 'text/plain'
    end
  end

  # PH_CUSTOMIZATION: Set CORS access control headers
  def cors_set_access_control_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    headers['Access-Control-Max-Age'] = "1728000"
  end

  # PH_CUSTOMIZATION: Don't verify the CSRF token on the CORS preflight
  def verify_authenticity_token_on_destroy
    return if request.method.to_s.downcase == 'options'
    verify_authenticity_token
  end

end
