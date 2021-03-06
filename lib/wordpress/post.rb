module Refinery
  module WordPress
    class Post < Page
      def tags
        # xml dump has "post_tag" for wordpress 3.1 and "tag" for 3.0
        path = if node.xpath("category[@domain='post_tag']").count > 0
          "category[@domain='post_tag']"
        else
          "category[@domain='tag']"
        end

        node.xpath(path).collect do |tag_node| 
          Tag.new(tag_node.text)
        end
      end

      def tag_list
        tags.collect(&:name).join(',')
      end

      def categories
        node.xpath("category[@domain='category']").collect do |cat|
          Category.new(cat.text)
        end
      end

      def comments
        node.xpath("wp:comment").collect do |comment_node|
          Comment.new(comment_node)
        end
      end

      def to_refinery
        print "."
        user = ::User.find_by_username(creator) || ::User.first
        raise "Referenced User doesn't exist! Make sure the authors are imported first." \
          unless user
            
        # check to see if post has a bookmark (only ivanenviroman.com)
        isBookmark = false
        bookmark_url = " " 
        meta_keys = node.xpath("wp:postmeta/wp:meta_key")
        if meta_keys.size > 0
          ib_index = 0
          sp_index = 0
          meta_keys.each do |key|
            if key.text == "isBookmark"
              isBookmark = true
            end
            if key.text == "syndication_permalink"
              meta_values = node.xpath("wp:postmeta/wp:meta_value")
              bookmark_url = meta_values[sp_index].text
            end
            ib_index += 1
            sp_index += 1
          end
        end

        if isBookmark
          begin
            #make a bookmark link
            bookmark = ::Link.new :title => title,
                                  :link => bookmark_url,
                                  :body => content_formatted,
                                  :draft => draft?,
                                  :published_at => post_date,
                                  :created_at => post_date,
                                  :author => user,
                                  :tag_list => tag_list
            bookmark.save!
          rescue
            #report a link (bookmark) error
          end
        else
          #create a post
          begin
          post = ::BlogPost.new :title => title, :body => content_formatted  + "Read more at here: #{bookmark_url} ",
            :draft => draft?, :published_at => post_date, :created_at => post_date,
            :author => user, :tag_list => tag_list
          post.save!

          ::BlogPost.transaction do
            categories.each do |category|
              post.categories << category.to_refinery
            end

            comments.each do |comment|
              comment = comment.to_refinery
              comment.post = post
              comment.save
            end
          end
        rescue ActiveRecord::RecordInvalid
          # if the title has already been taken (WP allows duplicates here,
          # refinery doesn't) append the post_id to it, making it unique
          post.title = "#{title}-#{post_id}"
          post.save
        end
        end
       


        post
      end

      def self.create_blog_page_if_necessary
        # refinerycms wants a page at /blog, so let's make sure there is one
        # taken from the original db seeds from refinery-blog
        unless ::Page.where("link_url = ?", '/blog').exists?
          page = ::Page.create(
            :title => "Blog",
            :link_url => "/blog",
            :deletable => false,
            :position => ((::Page.maximum(:position, :conditions => {:parent_id => nil}) || -1)+1),
            :menu_match => "^/blogs?(\/|\/.+?|)$"
          )

          ::Page.default_parts.each do |default_page_part|
            page.parts.create(:title => default_page_part, :body => nil)
          end
        end
      end

    end
  end
end
