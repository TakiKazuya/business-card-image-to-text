require 'line/bot'
require "tempfile"
require "sinatra"
require 'google-cloud-vision'

class String
  def fetch_postal_code
    self.slice(/\d{3}-?\d{4}/)
  end

  def fetch_phone_number
    self.slice(/(((0(\d{1}[-(]?\d{4}|\d{2}[-(]?\d{3}|\d{3}[-(]?\d{2}|\d{4}[-(]?\d{1}|[5789]0[-(]?\d{4})[-)]?)|\d{1,4}\-?)\d{4}|0120[-(]?\d{3}[-)]?\d{3})/)
  end

  def include_company_name?
    self.match?(/^.*(会社|事業所|研究所).*$/)
  end
end


get '/' do
  'hello world!'
end

post "/callback" do
  body = request.body.read
  signature = request.env["HTTP_X_LINE_SIGNATURE"]

  # unless client.validate_signature(body, signature)
  #   puts 'signature_error'
  #   error 400 do
  #     "Bad Request"
  #   end
  # end

  events = client.parse_events_from(body)
  events. each do |e|
    next unless e == Line::Bot::Event::Message ||  e.type == Line::Bot::Event::MessageType::Image

    response = @client.get_message_content(e.message['id'])
    case response
    when Net::HTTPSuccess
      tempfile = Tempfile.new(["tempfile", '.jpg']).tap do |file|
        file.write(response.body)
      end

      begin
        texts = image_to_texts(tempfile.path)
        parse_business_card_result = parse_business_card(texts)
        client.reply_message(e['replyToken'], {
          type: 'text',
          text: parse_business_card_result.join
        })
      rescue => e
        puts e.message
        client.reply_message(e['replyToken'], {
          type: 'text',
          text: "解析に失敗しました"
        })
      end
    else
      puts response.code
      puts response.body
      client.reply_message(e['replyToken'], {
        type: 'text',
        text: 'ネットワークエラー'
      })
    end
  end

  "OK"
end


def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_id = ENV["LINE_CHANNEL_ID"]
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def image_to_texts(image_path)
  image_annotator = Google::Cloud::Vision.image_annotator

  response = image_annotator.text_detection(
    image: image_path,
    max_results: 1 # optional, defaults to 10
  )

  result = [
    { "住所" => [] },
    { "電話番号" => [] },
    {}
  ]
  response.responses.each do |res|
    res.text_annotations.each do |text|
      result << text.description
    end
  end

  result
end

def parse_business_card(str_array)
  result = { company_name: [], phone_number: [], postal_code: [] }
  str_array.each do |e|
    result[:company_name] << e if e.include_company_name?
    result[:phone_number] << e.fetch_phone_number unless e.fetch_phone_number.nil?
    result[:postal_code] << e.fetch_postal_code unless e.fetch_postal_code.nil?
  end

  result
end
