module NUSBotgram
  module DataTypes
    # Telegram InlineQueryResultVenue data type
    #
    # @attr [String] type Type of the result, must be venue
    # @attr [String] id Unique identifier for this result, 1-64 Bytes
    # @attr [Float] latitude Location latitude in degrees
    # @attr [Float] longitude Location longitude in degrees
    # @attr [String] title Location title
    # @attr [String] address Address of the venue
    # @attr [String] foursquare_id Optional. Foursquare identifier of the venue if known
    # @attr [InlineKeyboardMarkup] reply_markup Optional. Inline keyboard attached to the message
    # @attr [InputMessageContent] input_message_content Content of the message to be sent
    # @attr [String] thumb_url Optional. URL of the thumbnail for the file
    # @attr [Integer] thumb_width Optional. Thumbnail width
    # @attr [Integer] thumb_height Optional. Thumbnail height
    #
    # See more at https://core.telegram.org/bots/api#inlinequeryresultvenue
    class InlineQueryResultVenue < NUSBotgram::DataTypes::Base
      attribute :type, String, default: 'venue'
      attribute :id, String
      attribute :latitude, Float
      attribute :longitude, Float
      attribute :title, String
      attribute :address, String
      attribute :foursquare_id, String
      attribute :reply_markup, InlineKeyboardMarkup
      attribute :input_message_content, InputMessageContent
      attribute :thumb_url, String
      attribute :thumb_width, Integer
      attribute :thumb_height, Integer
    end
  end
end