require "test_helper"

class ArSerializerTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::ArSerializer::VERSION
  end

  def test_field
    post = Post.first
    assert_equal(
      { title: post.title, body: post.body },
      ArSerializer.serialize(post, [:title, :body])
    )
  end

  def test_namespace
    user = User.first
    assert_raises { ArSerializer.serialize user, :bar }
    assert_equal({ bar: :bar }, ArSerializer.serialize(user, :bar, use: :aaa))
    assert_equal({ bar: :bar }, ArSerializer.serialize(user, :bar, use: :bbb))
    assert_equal({ foo: :foo1 }, ArSerializer.serialize(user, :foo, use: :bbb))
    assert_equal({ foo: :foo2 }, ArSerializer.serialize(user, :foo, use: :aaa))
    assert_equal({ foo: :foo2, foobar: :foobar }, ArSerializer.serialize(user, [:foo, :foobar], use: [:aaa, :bbb]))
  end

  def test_field_specify_modes
    post = Post.first
    expected = { title: post.title }
    queries = [
      :title,
      [:title],
      { attributes: :title },
      { attributes: [:title] }
    ]
    queries.each do |query|
      assert_equal expected, ArSerializer.serialize(post, query)
    end
  end

  def test_children
    user = Post.first.user
    expected = {
      name: user.name,
      posts: user.posts.map { |p| { title: p.title } }
    }
    assert_equal expected, ArSerializer.serialize(user, [:name, posts: :title])
  end

  def test_context
    star = Star.first
    user = star.user
    post = star.comment.post
    expected = {
      comments: post.comments.map do |c|
        { current_user_stars: c.stars.where(user: user).map { |s| { id: s.id } } }
      end
    }
    data = ArSerializer.serialize(
      post,
      { comments: { current_user_stars: :id } },
      context: { current_user: user }
    )
    assert_equal expected, data
  end

  def test_custom_preloader
    post = Star.first.comment.post
    expected = {
      comments: post.comments.map do |c|
        { stars_count_x5: c.stars.count * 5 }
      end
    }
    assert_equal expected, ArSerializer.serialize(post, comments: :stars_count_x5)
  end

  def test_count_preloader
    post = Star.first.comment.post
    expected = {
      comments: post.comments.map do |c|
        { stars_count: c.stars.count }
      end
    }
    assert_equal expected, ArSerializer.serialize(post, comments: :stars_count)
  end

  def test_alias_column
    post = Comment.first.post
    expected = {
      TITLE: post.title,
      body: post.body,
      COMMENTS: post.comments.map do |c|
        {
          id: c.id,
          BODY: c.body
        }
      end
    }
    query = [
      :body,
      title: { as: :TITLE },
      comments: {
        as: :COMMENTS,
        attributes: [
          :id,
          body: { as: :BODY }
        ]
      }
    ]
    assert_equal expected, ArSerializer.serialize(post, query)
  end

  def test_query_count
    user = Star.first.comment.post.user
    query = {
      posts: {
        comments: [
          :stars_count,
          :stars_count_x5,
          user: :name,
          stars: { user: :name },
          current_user_stars: :id
        ]
      }
    }
    context = { current_user: Star.first.user }
    count, _result = SQLCounts.count do
      ArSerializer.serialize(user, query, context: context)
    end
    assert_equal 8, count
  end
end
