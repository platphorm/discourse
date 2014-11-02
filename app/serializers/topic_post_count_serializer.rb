class TopicPostCountSerializer < BasicUserSerializer

  attributes :post_count

  def id
    object[:user].id
  end

  # PH_CUSTOMIZATIONS: Needs to match BasicUserSerializer
  def name
    object[:user].name
  end

  def username
    object[:user].username
  end

  def post_count
    object[:post_count]
  end

  def uploaded_avatar_id
    object[:user].uploaded_avatar_id
  end

end
