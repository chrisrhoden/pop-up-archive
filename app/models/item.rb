class Item < ActiveRecord::Base

  acts_as_paranoid

  include Tire::Model::Callbacks
  include Tire::Model::Search

  DEFAULT_INDEX_PARAMS = {}
  
  STANDARD_ROLES = ['producer', 'interviewer', 'interviewee', 'creator', 'host']

  before_validation :set_defaults, if: :new_record?

  before_update :handle_collection_change, if: :collection_id_changed?

  def handle_collection_change
    # do nothing if item has its own storage config defined
    # this means that it has already been explicitly set to this storage. leave it be
    return true if (storage_configuration)

    # if there is no change in collection id, no need to change
    return true unless (collection_id_was && collection_id)

    # get a handle on current and past collections
    collection_was = Collection.find(collection_id_was)
    collection_is  = Collection.find(collection_id)

    # if this is the same storage bucket and provider, leave it be
    return true if (collection_was.default_storage == collection_is.default_storage)

    # ----------
    # OK - if we are here, then we need to move the item and deal with the consequences
    # ----------

    # set the item visibility to that of the new collection
    self.is_public = collection_is.items_visible_by_default

    # move each audio file to new collection storage
    self.audio_files.each do |af|
      if af.storage_configuration

        # af already stored in the right place? remove association to af specific storage
        if af.storage_configuration == collection_is.default_storage
          af.storage_configuration = nil
          af.update_attribute(:storage_id, nil)

        # af NOT stored in the right place? move it to the correct storage for this item
        else
          af.copy_to_item_storage
        end
      else
        # no storage defined at the audio file level; af should be at collection_was storage
        # updating af triggers af.process_update_file -> copy_to_item_storage, so don't explictly call it here
        # logger.debug "af #{af.id} has no storage, set to was: #{collection_was.default_storage.inspect}"
        af.update_attributes({storage_configuration: collection_was.default_storage, storage_id: collection_was.default_storage_id}, without_protection: true)
      end
    end
    true
  end

  tire do
    mapping do
      indexes :id, index: :not_analyzed
      indexes :is_public, index: :not_analyzed
      indexes :collection_id, index: :not_analyzed
      indexes :date_created,          type: 'date',   include_in_all: false
      indexes :date_broadcast,        type: 'date',   include_in_all: false
      indexes :created_at,            type: 'date',   include_in_all: false, index_name:"date_added"
      indexes :description,           type: 'string'
      indexes :identifier,            type: 'string',  boost: 2.0
      indexes :title,                 type: 'string',  boost: 2.0
      indexes :tags,                  type: 'string',  index_name: "tag",    index: "not_analyzed"
      indexes :contributors,          type: 'string',  index_name: "contributor"
      indexes :physical_location,     type: 'string'
      indexes :transcription,         type: 'string'

      indexes :transcripts do
        indexes :audio_file_id, type: 'long', index: "not_analyzed"
        indexes :start_time, type: 'long', index: "not_analyzed"
        indexes :confidence, type: 'float', index: 'not_analyzed'
        indexes :transcripts, type: 'string', store: true
      end
      
      indexes :duration,          type: 'long',    include_in_all: false
      indexes :location do
        indexes :name
        indexes :position, type: 'geo_point'
      end

      indexes :entities do 
        indexes :name, type: 'string'
        indexes :category, type: 'string'
      end

      STANDARD_ROLES.each do |role|
        indexes role.pluralize.to_sym, type: 'string', include_in_all: false, index_name: role, index: "not_analyzed"
      end

    end
  end
  
  attr_accessible :date_broadcast, :date_created, :date_peg,
    :description, :digital_format, :digital_location, :duration,
    :episode_title, :extra, :identifier, :music_sound_used, :notes,
    :physical_format, :physical_location, :rights, :series_title,
    :tags, :title, :transcription, :adopt_to_collection

  belongs_to :geolocation
  belongs_to :csv_import
  belongs_to :storage_configuration, class_name: "StorageConfiguration", foreign_key: :storage_id
  belongs_to :collection, :with_deleted => true

  has_many   :collection_grants, through: :collection
  has_many   :users, through: :collection_grants

  has_many   :instances, dependent: :destroy
  has_many   :audio_files, dependent: :destroy
  has_many   :transcripts, through: :audio_files

  has_many   :contributions, dependent: :destroy
  has_many   :contributors, through: :contributions, source: :person
  
  has_many   :entities, dependent: :destroy
  
  STANDARD_ROLES.each do |role|
    has_many "#{role}_contributions".to_sym, class_name: "Contribution", conditions: {role: role}
    has_many role.pluralize.to_sym, through: "#{role}_contributions".to_sym, source: :person
  end

  default_scope includes(:contributors, :interviewees, :interviewers, :hosts, :creators, :producers, :geolocation)

  serialize :extra, HstoreCoder

  delegate :title, to: :collection, prefix: true

  accepts_nested_attributes_for :contributions

  @@instance_lock = Mutex.new

  def process_analysis(analysis)
    existing_names = self.entities.collect{|e| e.name || ''}.sort.uniq
    analysis = JSON.parse(analysis) if analysis.is_a?(String)
    ["entities", "locations", "relations", "tags", "topics"].each do |category|
      analysis[category].each{|analysis_entity|
        name = analysis_entity.delete('name')
        next if (name.blank? || existing_names.include?(name))

        entity = self.entities.build
        entity.category     = category.try(:singularize)
        entity.entity_type  = analysis_entity.delete('type')
        entity.is_confirmed = false
        entity.name         = name
        entity.identifier   = analysis_entity.delete('guid')
        entity.score        = analysis_entity.delete('score')

        # anything left over, put it in the extra
        entity.extra        = analysis_entity
        entity.save
      }
    end
  end

  def dedupe_entities
    groups =  self.entities.group_by(&:name)
    groups.each do |k,v|
      next if k.blank?
      keep = v.detect{|e| e.is_confirmed?} || v.first
      v.each{|v| v.destroy unless v == keep}
    end
  end

  def token
    read_attribute(:token) || update_token
  end

  def update_token
    @@instance_lock.synchronize do
      begin
        t = "#{hosterize((self.title||'untitled')[0,50])}." + generate_token(6) + ".popuparchive.org"
      end while Item.where(:token => t).exists?
      self.update_attribute(:token, t)
      t
    end
  end

  def generate_token(length=10)
    cs = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a
    SecureRandom.random_bytes(length).each_char.map{|c| cs[(c.ord % cs.length)]}.join
  end

  # like parameterize, but no '_'
  def hosterize(string, sep = '-')
    # replace accented chars with their ascii equivalents
    parameterized_string = ActiveSupport::Inflector.transliterate(string).downcase
    # Turn unwanted chars into the separator
    parameterized_string.gsub!(/[^a-z0-9\-]+/, sep)
    unless sep.nil? || sep.empty?
      re_sep = Regexp.escape(sep)
      # No more than one of the separator in a row.
      parameterized_string.gsub!(/#{re_sep}{2,}/, sep)
      # Remove leading/trailing separator.
      parameterized_string.gsub!(/^#{re_sep}|#{re_sep}$/, '')
    end
    parameterized_string
  end

  def upload_to
    storage.direct_upload? ? storage : collection.upload_to
  end

  def storage
    self.storage_configuration || self.collection.default_storage
  end

  def geographic_location=(name)
    self.geolocation = Geolocation.for_name(name)
  end

  def geographic_location
    geolocation.name
  end

  def creator=(creator)
    self.creators = [creator]
  end

  def creator
    self.creators.try(:first)
  end

  def transcription
    transcript_text || super
  end

  def transcript_text
    audio_files.collect{|af| af.transcript_text}.join("\n")
  end

  def to_indexed_json(params={})
    as_json(params.reverse_merge(DEFAULT_INDEX_PARAMS)).tap do |json|
      ([:contributors] + STANDARD_ROLES.collect{|r| r.pluralize.to_sym}).each do |assoc|
        json[assoc]      = send(assoc).map{|c| c.as_json } 
      end
      json[:tags]        = tags_for_index
      json[:location]    = geolocation.to_indexed_json if geolocation.present?
      json[:transcripts] = transcripts_for_index
    end.to_json
  end

  def tags
    super || self.tags = []
  end

  def adopt_to_collection=(collection_id)
    self.collection_id = collection_id
  end

  def set_defaults
    return true unless is_public.nil?
    self.is_public = (collection.present? && collection.items_visible_by_default)
    true
  end

  private

  def tags_for_index
    tags.dup.tap do |tfi|
      tags.each do |tag|
        parts = tag.split('/')
        1.upto(parts.size-1) do |number|
          tfi.push(parts[0...number].join('/'))
        end
      end
    end
  end

  def transcripts_for_index
    transcripts.map(&:timed_texts).flatten.map {|text| text.as_indexed_json }
  end
end
