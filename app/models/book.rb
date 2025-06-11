class Book < ApplicationRecord
  validates :title, presence: true

  after_create_commit :fetch_book_data
  after_update_commit :fetch_book_data, if: :title_changed?

  def thumbnail_url
    payload.first["thumbnail"]
  end

  has_many_attached :pdfs
  has_many_attached :audios

  def self.ransackable_attributes(auth_object = nil)
    %w[title]
  end

  private

  def fetch_book_data
    payload = ::GoogleBookService.search_books(title)
    update(payload: payload.first)
  end
end
