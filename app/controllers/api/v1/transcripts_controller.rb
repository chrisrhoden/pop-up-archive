class Api::V1::TranscriptsController < Api::V1::BaseController
  expose :items, ancestor: :current_user
  expose :item
  expose :audio_files, ancestor: :item
  expose :audio_file
  expose(:transcript) { audio_file.timed_transcript }

  respond_to :xml

  def show
    send_data render_to_string, disposition: %(attachment; filename="#{audio_file.filename}.transcript.#{params[:format]}")
  end
end