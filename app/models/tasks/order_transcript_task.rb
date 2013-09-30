class Tasks::OrderTranscriptTask < Task

  state_machine :status do
    after_transition any => :complete do |task, transition|

      if task.owner && !Rails.env.test?
        # process callback amara which will indicate that the transcript has been completed
        # may be callback from amara, or maybe from mobileworks...
      end

    end
  end

  after_commit :order_transcript, on: :create

  def order_transcript
    return if video_id
    logger.debug("OrderTranscriptTask #{self.id}: order_transcript start")
    # create the job at amara
    video = create_video
    # save the video_id, which is useful for crafting a url
    self.extras['video_id'] = video.id
    self.save!

    # create task for mobile worker with this video url (and language specified?)
    # first we probably need a gem for that...
  end

  def create_video
    logger.debug("OrderTranscriptTask: create_video start")
    response = amara_client.videos.create(amara_options)
    video = response.object
    logger.debug("amara video created: #{video.inspect}")
    video
  end

  def audio_file
    owner
  end

  def video_id
    self.extras['video_id']
  end

  def video_url
    # audio_file.url(:ogg)
    audio_file.public_url(extension: :ogg)
  end

  def language
    audio_file.item.language ? audio_file.item.language.split('-')[0].downcase : 'en' rescue 'en'
  end

  def team
    ENV['AMARA_TEAM_PRIVATE'] || 'prx-test-1' # this should be an env constant perhaps?
  end

  def amara_options
    options = {
      # duration: audio_file.duration, # don't have this, could get from fixer analysis perhaps?
      team:      team,
      title:     audio_file.filename,
      video_url: video_url,
      primary_audio_language_code: language
    }

    logger.debug "amara options: #{options.inspect}"

    options
  end

  def get_transcript
    r = amara_client.videos(t.video_id).languages(language).subtitles.get
    r.object
  end

  def load_subtitles(subtitles)
    transcript = nil
    if subtitles && subtitles.subtitles && subtitles.subtitles.count > 0
      version = subtitles.version_number.to_i
      if version > 0 && version > self.extras['subtitles_version'].to_i

        full_language = (audio_file.item.language || 'en-US')
        identifier    = "#{audio_file.id}_#{language}"
        transcript    = audio_file.item.transcripts.build(language: full_language, identifier: identifier, start_time: 0, end_time: 0, confidence: 100)

        subtitles.subtitles.each do |row|
          tt = transcript.timed_texts.build({
            start_time: (row.start.to_i / 1000.00).round,
            end_time:   (row.end.to_i   / 1000.00).round,
            confidence: 100,
            text:       row.text
          })
          transcript.end_time = tt.end_time if ((tt.end_time > transcript.end_time) || (transcript.end_time <= 0))
          transcript.start_time = tt.start_time if ((tt.start_time < transcript.start_time) || (transcript.start_time <= 0))
        end
        transcript.confidence = 100
        self.extras['subtitles_version'] = version
        transcript.save! && self.save!
      end
    end
    transcript
  end

  def amara_client
    @client ||= Amara::Client.new(
      api_key:      ENV['AMARA_KEY'],
      api_username: ENV['AMARA_USERNAME'],
      endpoint:     ENV['AMARA_ENDPOINT']
    )
  end

  def edit_video_transcript_url
    raise 'no url possible unless video id present' if video_id.blank?

    # "http://www.amara.org/en/subtitles/editor/#{video_id}/en/"
    # "http://staging.amara.org/en/videos/5eZU6jdDRfQ2/info/hive_trimwav/"

    "http://#{ENV['AMARA_HOST']}/en/onsite_widget/?config=" + edit_video_transcript_url_options
  end

  def edit_video_transcript_url_options
    URI.encode({
      videoID:           video_id,
      videoURL:          video_url,
      effectiveVideoURL: video_url,
      languageCode:      language
    }.to_json)
  end

end
