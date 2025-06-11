class BooksController < ApplicationController
  before_action :set_book, only: [ :show ]

  def index
    @books = Book.where.not(payload: nil)
  end

  def show
  end

  private

  def set_book
    @book = Book.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to books_path
  end
end
