require "json"
require "./libtexsmart"

class Texsmart
  def initialize(data_path : String = "/srv/qq_ts/data/nlu/kb/", worker_count : Int32 = 6)
    @engine = LibTexSmart.create_engine(data_path, worker_count)
  end

  def finalize
    LibTexSmart.destroy_engine(@engine)
  end

  struct Term
    include JSON::Serializable

    getter str : String
    getter idx : UInt32
    getter tag : String

    def initialize(@str, @idx, @tag)
    end
  end

  NO_NER = {
    word_seg: {enable_phrase: false, person_as_one_word: true, location_as_one_word: true, organization_as_one_word: true},
    ner: {enable: false}, fnr: {enable: false}, srl: {enable: false},
  }.to_json

  def parse_no_ner(input : String, options = NO_NER)
    output = LibTexSmart.parse_utf8_text_ext(@engine, input.to_slice, input.bytesize, options)
    words = get_words(output)
    LibTexSmart.destroy_output(output)
    words
  end

  WITH_NER = {
    word_seg: {enable_phrase: false, person_as_one_word: true, location_as_one_word: true, organization_as_one_word: true},
    ner: {enable: true, alg: "coarse.crf"}, fnr: {enable: false}, srl: {enable: false},
  }.to_json

  def parse_with_ner(input : String, options = OPTIONS)
    output = LibTexSmart.parse_utf8_text_ext(@engine, input.to_slice, input.bytesize, options)

    words = get_words(output)
    entities = get_entities(output)
    LibTexSmart.destroy_output(output)

    {words, entities}
  end

  private def get_words(output : LibTexSmart::NluOutputHandle)
    words = LibTexSmart.get_words(output)
    slice = Slice(LibTexSmart::NluTerm).new(words.items, words.size)

    slice.map do |word|
      Term.new(str: read_str(word.str), idx: word.offset, tag: read_str(word.tag))
    end
  end

  private def get_phrases(output : LibTexSmart::NluOutputHandle)
    phrases = LibTexSmart.get_phrases(output)
    slice = Slice(LibTexSmart::NluTerm).new(phrases.items, phrases.size)

    slice.map do |phrase|
      Term.new(
        str: read_str(phrase.str),
        idx: phrase.offset,
        tag: read_str(phrase.tag),
      )
    end
  end

  struct Entity
    include JSON::Serializable

    getter str : String
    getter idx : UInt32
    getter type : String
    getter meaning : String

    def initialize(@str, @idx, @type, @meaning)
    end
  end

  private def get_entities(output : LibTexSmart::NluOutputHandle)
    entities = LibTexSmart.get_entities(output)
    slice = Slice(LibTexSmart::NluEntity).new(entities.items, entities.size)

    slice.map do |entity|
      Entity.new(
        str: read_str(entity.str),
        idx: entity.offset,
        type: read_str(entity.type.name),
        meaning: read_str(entity.meaning)
      )
    end
  end

  @[AlwaysInline]
  private def read_str(str : Pointer(UInt16)) : String
    String.from_utf16(str).first
  end

  @[AlwaysInline]
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
