class Conversations::PdfTranscriptBuilder
  PAGE_MARGIN = 40
  AVATAR_DIAMETER = 28
  AVATAR_PALETTE = %w[1F93FF 6D4AFF FF9F43 2BD4B3 FF6B81 4B7BEC F7B731 26DE81].freeze

  BUBBLE_PADDING_X = 10
  BUBBLE_PADDING_Y = 8
  BUBBLE_RADIUS = 8
  GAP_AVATAR_BUBBLE = 8
  NAME_HEIGHT = 12
  TIMESTAMP_HEIGHT = 11
  MESSAGE_GAP = 16
  MAX_BUBBLE_WIDTH_RATIO = 0.62
  BODY_FONT_SIZE = 10

  OUTGOING_BG = '1F93FF'.freeze
  OUTGOING_TEXT = 'FFFFFF'.freeze
  INCOMING_BG = 'F0F2F5'.freeze
  INCOMING_TEXT = '1F2933'.freeze
  HEADING_COLOR = '10151A'.freeze
  MUTED_COLOR = '899096'.freeze
  BLACK = '000000'.freeze

  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
    @contact = conversation.contact
    @agent = conversation.assignee
    @inbox = conversation.inbox
    @messages = conversation.messages.chat.select(&:conversation_transcriptable?)
  end

  def render
    @pdf = Prawn::Document.new(page_size: 'A4', margin: PAGE_MARGIN)

    render_header
    @messages.each { |message| render_message(message) }

    @pdf.render
  end

  private

  attr_reader :pdf

  def render_header
    pdf.fill_color OUTGOING_BG
    pdf.text sanitize(@account&.name).to_s, size: 9, style: :bold
    pdf.fill_color HEADING_COLOR
    pdf.move_down 2
    pdf.text "Conversation ##{@conversation.display_id}", size: 18, style: :bold
    pdf.move_down 8
    pdf.fill_color MUTED_COLOR
    pdf.text "Contact: #{sanitize(@contact&.name) || 'N/A'}", size: 9
    pdf.text "Assigned agent: #{sanitize(@agent&.available_name) || 'Unassigned'}", size: 9
    pdf.text "Inbox: #{sanitize(@inbox&.name) || 'N/A'}", size: 9
    pdf.text "Started on: #{@conversation.created_at.strftime('%b %d, %Y %I:%M %p')}", size: 9
    pdf.move_down 10
    pdf.stroke_color 'E4E7EB'
    pdf.stroke_horizontal_rule
    pdf.stroke_color BLACK
    pdf.fill_color BLACK
    pdf.move_down 18
  end

  def render_message(message)
    outgoing = message.outgoing?
    sender_name = sanitize(message.sender&.try(:available_name) || message.sender&.try(:name) || 'Bot')
    body = message_body(message)
    bubble_width, body_height = measure_bubble(body)
    bubble_height = body_height + (2 * BUBBLE_PADDING_Y)
    block_height = NAME_HEIGHT + bubble_height + TIMESTAMP_HEIGHT + MESSAGE_GAP

    ensure_space(block_height)

    top_y = pdf.y
    bubble_x = outgoing ? pdf.bounds.right - AVATAR_DIAMETER - GAP_AVATAR_BUBBLE - bubble_width : AVATAR_DIAMETER + GAP_AVATAR_BUBBLE
    avatar_x = outgoing ? pdf.bounds.right - AVATAR_DIAMETER : 0
    align = outgoing ? :right : :left

    pdf.fill_color(outgoing ? OUTGOING_BG : HEADING_COLOR)
    pdf.text_box sender_name, at: [bubble_x, top_y], width: bubble_width, height: NAME_HEIGHT, size: 9, style: :bold, align: align

    bubble_top = top_y - NAME_HEIGHT
    draw_avatar(avatar_x, bubble_top, avatar_color_for(sender_name), initials_for(sender_name))

    pdf.fill_color(outgoing ? OUTGOING_BG : INCOMING_BG)
    pdf.rounded_rectangle [bubble_x, bubble_top], bubble_width, bubble_height, BUBBLE_RADIUS
    pdf.fill

    pdf.fill_color(outgoing ? OUTGOING_TEXT : INCOMING_TEXT)
    pdf.text_box body, at: [bubble_x + BUBBLE_PADDING_X, bubble_top - BUBBLE_PADDING_Y],
                        width: bubble_width - (2 * BUBBLE_PADDING_X), height: body_height, size: BODY_FONT_SIZE

    pdf.fill_color MUTED_COLOR
    pdf.text_box formatted_timestamp(message), at: [bubble_x, bubble_top - bubble_height], width: bubble_width,
                                                 height: TIMESTAMP_HEIGHT, size: 7.5, align: align

    pdf.fill_color BLACK
    pdf.move_down block_height
  end

  def draw_avatar(x, top_y, color, initials)
    radius = AVATAR_DIAMETER / 2.0
    pdf.fill_color color
    pdf.fill_circle [x + radius, top_y - radius], radius
    pdf.fill_color 'FFFFFF'
    pdf.text_box initials, at: [x, top_y], width: AVATAR_DIAMETER, height: AVATAR_DIAMETER,
                            align: :center, valign: :center, size: 9, style: :bold
  end

  def ensure_space(height)
    pdf.start_new_page if pdf.y - height < pdf.bounds.bottom
  end

  def message_body(message)
    parts = []

    if @inbox&.inbox_type == 'Email'
      subject = message.content_attributes.dig(:email, :subject)
      parts << "Subject: #{sanitize(subject)}" if subject.present?
    end

    parts << plain_text_content(message) if message.content.present?

    message.attachments.each do |attachment|
      parts << "Attachment: #{sanitize(attachment.file&.filename.to_s)}"
    end

    parts.join("\n\n").presence || '[no content]'
  end

  def measure_bubble(body)
    max_width = pdf.bounds.width * MAX_BUBBLE_WIDTH_RATIO
    inner_max_width = max_width - (2 * BUBBLE_PADDING_X)

    natural_width = body.include?("\n") ? inner_max_width + 1 : pdf.width_of(body, size: BODY_FONT_SIZE) + 2

    if natural_width <= inner_max_width
      [natural_width + (2 * BUBBLE_PADDING_X), pdf.height_of(body, width: natural_width, size: BODY_FONT_SIZE)]
    else
      [max_width, pdf.height_of(body, width: inner_max_width, size: BODY_FONT_SIZE)]
    end
  end

  def plain_text_content(message)
    html = ChatwootMarkdownRenderer.new(message.content).render_message.to_s
    html = html.gsub(%r{<br\s*/?>}i, "\n").gsub(%r{</p>}i, "\n\n")
    sanitize(ActionController::Base.helpers.strip_tags(html).strip)
  end

  def formatted_timestamp(message)
    message.created_at.in_time_zone(@inbox&.timezone.presence || 'UTC').strftime('%b %d, %Y %I:%M %p')
  end

  def initials_for(name)
    return '?' if name.blank?

    parts = name.strip.split(/\s+/)
    initials = parts.length > 1 ? "#{parts.first[0]}#{parts.last[0]}" : parts.first[0, 2]
    initials.upcase
  end

  def avatar_color_for(name)
    return AVATAR_PALETTE.first if name.blank?

    AVATAR_PALETTE[name.sum % AVATAR_PALETTE.length]
  end

  # Prawn's built-in fonts (Helvetica) only support the Windows-1252 charset.
  # Emoji and other characters outside it raise Prawn::Errors::IncompatibleStringEncoding,
  # so we drop anything unsupported instead of crashing the whole PDF.
  def sanitize(text)
    return nil if text.nil?

    text.to_s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '').encode('UTF-8')
  end
end
