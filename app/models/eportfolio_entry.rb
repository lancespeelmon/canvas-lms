#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class EportfolioEntry < ActiveRecord::Base
  attr_accessible :eportfolio, :eportfolio_category, :name, :artifact_type, :attachment, :allow_comments, :show_comments, :url, :content
  attr_readonly :eportfolio_id, :eportfolio_category_id
  belongs_to :eportfolio
  belongs_to :eportfolio_category
  acts_as_list :scope => :eportfolio_category
  before_save :infer_unique_slug
  before_save :infer_comment_visibility
  after_save :update_portfolio
  validates_presence_of :eportfolio_id
  validates_presence_of :eportfolio_category_id
  has_many :page_comments, :as => :page, :include => :user, :order => 'page_comments.created_at DESC'
  
  adheres_to_policy
  
  serialize :content

  set_policy do
    given {|user, session| user && self.allow_comments }
    set { can :comment }
  end
  
  def infer_comment_visibility
    self.show_comments = false if !self.allow_comments
    true
  end
  protected :infer_comment_visibility
  
  def update_portfolio
    self.eportfolio.save!
  end
  protected :update_portfolio
  
  def content_sections
    (self.content || []).map do |section|
      if section.is_a?(Hash)
        section.with_indifferent_access
      else
        section
      end
    end
  end
  
  def submission_ids
    res = []
    content_sections.each do |section|
      res << section["submission_id"] if section["section_type"] == "submission"
    end
    res
  end
  
  def full_slug
    (self.eportfolio_category.slug rescue "") + "_" + self.slug
  end
  
  def attachments
    res = []
    content_sections.each do |section|
      res << (self.eportfolio.user.all_attachments.find_by_uuid(section["attachment_id"]) rescue nil) if section["section_type"] == "upload"
    end
    res.compact
  end
  
  def submissions
    res = []
    content_sections.each do |section|
      res << (self.eportfolio.user.submissions.find_by_id(section["submission_id"]) rescue nil) if section["section_type"] == "submission"
    end
    res.compact
  end

  def parse_content(params)
    cnt = params[:section_count].to_i rescue 0
    self.content = []
    cnt.times do |idx|
      obj = params[("section_" + (idx + 1).to_s).to_sym].slice(:section_type, :content, :submission_id, :attachment_id)
      new_obj = {:section_type => obj[:section_type]}
      if obj[:section_type] == 'rich_text' || obj[:section_type] == 'html'
        config = Instructure::SanitizeField::SANITIZE
        new_obj[:content] = Sanitize.clean(obj[:content] || '', config).strip
        new_obj = nil if new_obj[:content].empty?
      elsif obj[:section_type] == 'submission'
        submission = eportfolio.user.submissions.find_by_id(obj[:submission_id])
        if submission
          new_obj[:submission_id] = submission.id
        else
          new_obj = nil
        end
      elsif obj[:section_type] == 'attachment'
        attachment = eportfolio.user.attachments.active.find_by_id(obj[:attachment_id])
        if attachment
          new_obj[:attachment_id] = attachment.id
        else
          new_obj = nil
        end
      else
        new_obj = nil
      end
      
      if new_obj
          self.content << new_obj
      end
    end
    self.content << "No Content Added Yet" if self.content.empty?
  end

  
  def category_slug
    self.eportfolio_category.slug rescue self.eportfolio_category_id
  end
  
  def infer_unique_slug
    pages = self.eportfolio_category.eportfolio_entries rescue []
    self.name ||= "Page Name"
    self.slug = self.name.gsub(/[\s]+/, "_").gsub(/[^\w\d]/, "")
    match_cnt = pages.select{|p| p != self && p.slug && p.slug == self.slug}.length
    if match_cnt > 0
      self.slug = self.slug + "_" + (match_cnt + 1).to_s
    end
  end
  protected :infer_unique_slug

  def to_atom(opts={})
    Atom::Entry.new do |entry|
      entry.title     = "#{self.name}"
      entry.updated   = self.updated_at
      entry.published = self.created_at
      url = "http://#{HostUrl.default_host}/eportfolios/#{self.eportfolio_id}/#{self.eportfolio_category.slug}/#{self.slug}"
      url += "?verifier=#{self.eportfolio.uuid}" if opts[:private]
      entry.links    << Atom::Link.new(:rel => 'alternate', :href => url)
      entry.id        = "tag:#{HostUrl.default_host},#{self.created_at.strftime("%Y-%m-%d")}:/eportfoli_entries/#{self.feed_code}_#{self.created_at.strftime("%Y-%m-%d-%H-%M") rescue "none"}"
      rendered_content = "Click to view page content"
      entry.content   = Atom::Content::Html.new(rendered_content)
    end
  end
end
