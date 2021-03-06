require 'rubygems'
require 'sequel'
require 'fileutils'
require 'yaml'

# NOTE: This converter requires Sequel and the MySQL gems.
# The MySQL gem can be difficult to install on OS X. Once you have MySQL
# installed, running the following commands should work:
# $ sudo gem install sequel
# $ sudo gem install mysql -- --with-mysql-config=/usr/local/mysql/bin/mysql_config

module Jekyll
  module Drupal

    # Reads a MySQL database via Sequel and creates a post file for each
    # post in wp_posts that has post_status = 'publish'.
    # This restriction is made because 'draft' posts are not guaranteed to
    # have valid dates.
    QUERY = "SELECT n.nid, n.title, nr.body, n.created, n.status, GROUP_CONCAT(td.name) as categories FROM node n
      JOIN node_revisions nr ON n.vid = nr.vid
      LEFT JOIN term_node tn ON (n.nid = tn.nid AND n.vid = tn.vid)
      LEFT JOIN term_data td ON td.tid = tn.tid
      WHERE (n.type = 'blog' OR n.type = 'story')
      GROUP BY n.nid"

    def self.process(dbname, user, pass, host = 'localhost', port = 3306)
      db = Sequel.mysql(dbname, :user => user, :password => pass, :host => host, :port => port, :encoding => 'utf8')

      FileUtils.mkdir_p "_posts"
      FileUtils.mkdir_p "_drafts"

      # Create the refresh layout
      # Change the refresh url if you customized your permalink config
      File.open("_layouts/refresh.html", "w") do |f|
        f.puts <<EOF
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<meta http-equiv="refresh" content="0;url={{ page.refresh_to_post_id }}.html" />
</head>
</html>
EOF
      end

      db[QUERY].each do |post|
        # Get required fields and construct Jekyll compatible name
        node_id = post[:nid]
        title = post[:title]
        content = post[:body]
        created = post[:created]
        categories = post[:categories]
        time = Time.at(created)
        is_published = post[:status] == 1
        dir = is_published ? "_posts" : "_drafts"
        slug = title.strip.downcase.gsub(/(&|&amp;)/, ' and ').gsub(/[\s\.\/\\]/, '-').gsub(/[^\w-]/, '').gsub(/[-_]{2,}/, '-').gsub(/^[-_]/, '').gsub(/[-_]$/, '')
        name = time.strftime("%Y-%m-%d-") + slug + '.md'

        # Get the relevant fields as a hash, delete empty fields and convert
        # to YAML for the header

        categories_ = categories.split(',') unless categories.nil?
        data = {
           'layout' => 'post',
           'title' => title.to_s,
           'created' => created,
           'categories' => categories_,
         }.delete_if { |k,v| v.nil? || v == ''}.to_yaml

        # Write out the data and content to file
        File.open("#{dir}/#{name}", "w") do |f|
          f.puts data
          f.puts "---"
          f.puts content
        end

        # Make a file to redirect from the old Drupal URL
        if is_published
          FileUtils.mkdir_p "node/#{node_id}"
          File.open("node/#{node_id}/index.md", "w") do |f|
            f.puts "---"
            f.puts "layout: refresh"
            f.puts "refresh_to_post_id: /#{time.strftime("%Y/%m/%d/") + slug}"
            f.puts "---"
          end
        end
      end

      # TODO: Make dirs & files for nodes of type 'page'
        # Make refresh pages for these as well

      # TODO: Make refresh dirs & files according to entries in url_alias table
    end
  end
end
