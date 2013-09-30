require "digest/sha1"

class Tasks::UploadTask < Task

  state_machine :status do
    after_transition any => :complete do |task, transition|
      task.upload_complete
    end
  end

  def upload_complete
    # logger.debug "Tasks::UploadTask: after_transition: any => :complete start !!!!"

    if self.owner.nil?
      # logger.debug "Tasks::UploadTask: after_transition: any => :complete owner nil"
    else
      # logger.debug "Tasks::UploadTask: after_transition: any => :complete owner update file"
      # set the file on the owner, and the storage as the upload_to
      file_name = File.basename(self.extras['key'])
      upload_id = self.owner.upload_to.id

      self.owner.update_file!(file_name, upload_id)

      # now copy it to the right place if it needs to be (e.g. s3 -> ia)
      # or if it is in the right spot, transcribe it!
      unless self.owner(true).copy_to_item_storage
        self.owner(true).analyze_audio
        self.owner(true).transcode_audio
        self.owner(true).transcribe_audio
      end
      # logger.debug "Tasks::UploadTask: after_transition: any => :complete file updates over"
    end

    # logger.debug "Tasks::UploadTask: after_transition: any => :complete finish !!!!"

  rescue Exception => e
    logger.error e.message
    logger.error e.backtrace.join("\n")
  end

  before_validation(on: :create) do
    self.extras = {} unless extras
    self.extras['chunks_uploaded'] = [].to_csv unless self.extras.key?(:chunks_uploaded)
    self.identifier = Tasks::UploadTask.make_identifier(extras) unless identifier
  end

  # after_commit do
  #   return unless ((num_chunks > 0) && (num_chunks <= chunks_uploaded.size) && !complete?)
  #   self.finish!
  # end

  def num_chunks
    extras['num_chunks'].to_i
  end

  def add_chunk!(chunk)
    self.chunks_uploaded = (chunks_uploaded << chunk.to_i).sort.uniq
    save!
  end

  def chunks_uploaded
    (extras['chunks_uploaded'] || [].to_csv).parse_csv.map(&:to_i)
  end

  def chunks_uploaded=(chunks_array)
    self.extras ||= {}
    self.extras['chunks_uploaded'] = chunks_array.to_csv
  end

  def self.make_identifier(o=nil)
    raise 'you must pass in options to make an identifier' unless o
    Digest::SHA1.hexdigest("u:#{o[:user_id]};n:#{o[:filename]};s:#{o[:filesize]};m:#{o[:last_modified]}")
  end

end
