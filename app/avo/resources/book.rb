class Avo::Resources::Book < Avo::BaseResource
  self.title = :title
  self.external_link = lambda {
    main_app.book_path(record)
  }

  # self.includes = []
  self.attachments = [ :pdfs, :audios ]
  self.search = {
    query: -> { query.ransack(title_cont: params[:q], m: "or").result(distinct: false) }
  }

  def fields
    field :id, as: :id
    field :title, as: :text
    field :thumbnail, as: :external_image do
      record.thumbnail_url
    end
    field :payload, as: :code, disabled: true
    field :pdfs, as: :file, attach_many: true
    field :audios, as: :file, attach_many: true
  end
end
