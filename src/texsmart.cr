require "./libtexsmart"

# engine = LibTexSmart.create_engine("./data/nlu/kb/", 4)

# text = "上个月30号，南昌王先生在自己家里边看流浪地球边吃煲仔饭。"
# output = LibTexSmart.parse_utf8_text(engine, text.to_slice, text.bytesize)

# words = LibTexSmart.get_words(output)
# slice = Slice(LibTexSmart::NluTerm).new(words.items, words.size)

# slice.map do |token|
#   # LibTexSmart.print_str(token.str, true)

#   puts read_str(token.str)

#   # puts [str, tag, token.offset, token.len, token.start_token, token.token_count]
# end

# LibTexSmart.destroy_output(output)
# LibTexSmart.destroy_engine(engine)

class Texsmart
  def initialize(data_path : String = "./data/nlu/kb/", worker_count : Int32 = 4)
    @engine = LibTexSmart.create_engine(data_path, worker_count)
  end

  def finalize
    LibTexSmart.destroy_engine(@engine)
  end

  struct Term
    getter str : String
    getter idx : UInt32
    getter tag : String
    getter freq : UInt32

    def initialize(@str, @idx, @tag, @freq)
    end
  end

  def parse(input : String)
    output = LibTexSmart.parse_utf8_text(@engine, input.to_slice, input.bytesize)

    words = get_words(output)
    LibTexSmart.destroy_output(output)

    words
  end

  private def get_words(output : LibTexSmart::NluOutputHandle)
    words = LibTexSmart.get_words(output)
    slice = Slice(LibTexSmart::NluTerm).new(words.items, words.size)

    slice.map do |word|
      Term.new(
        str: read_str(word.str),
        idx: word.offset,
        tag: read_str(word.tag),
        freq: word.freq
      )
    end
  end

  private def read_str(str : Pointer(UInt16)) : String
    String.from_utf16(str).first
  end

  private def read_str(str : Pointer(UInt32)) : String
    String.build do |io|
      loop do
        byte = str.value.to_i
        break if byte == 0
        io << byte.unsafe_chr
        str += 1
      end
    end
  end
end

engine = Texsmart.new
puts engine.parse("上个月30号，南昌王先生在自己家里边看流浪地球边吃煲仔饭。")
