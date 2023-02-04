{% if flag?(:win32) %}
  @[Link(ldflags: "#{__DIR__}/../lib/tencent_ai_texsmart.lib")]
{% else %}
  @[Link(ldflags: "-I./include -L./lib -ltencent_ai_texsmart -Wl,-rpath='$ORIGIN/lib'")]
{% end %}
lib LibTexSmart
  alias CStr = LibC::Char*

  {% if flag?(:win32) %}
    alias String = UInt16*
  {% else %}
    alias String = UInt32*
  {% end %}

  struct TextNormOptions
    restore_case : Bool
    cht_to_chs : Bool # traditional to simplified Chinese
    to_lower : Bool
    char_to_norm_form : Bool
  end

  enum AsciiSegMode
    Simple = 0
    Whole  = 1
    Std    = 2
  end

  struct WordSegOptions
    enable : Bool
    ascii_seg_mode : UInt32
    ascii_seg_lm_mode : Bool
    ascii_seg_lm_pinyin : Bool
    ascii_seg_lm_comb : Bool

    use_customized_spec : Bool
    enable_phrase : Bool
    person_as_one_word : Bool
    location_as_one_word : Bool
    organization_as_one_word : Bool
  end

  struct PosTaggingOptions
    enable : Bool
    alg : String
  end

  struct NerOptions
    enable : Bool
    alg : String
    enable_deep_learning : Bool
    enable_ne_adjustment : Bool
    enable_fine_grained_ner : Bool
    enable_deep_representation : Bool
  end

  struct FnrOptions
    enable : Bool
  end

  struct SrlOptions
    enable : Bool
  end

  struct SyntacticParsingOptions
    enable : Bool
  end

  struct NluOptions
    text_norm : TextNormOptions
    word_seg : WordSegOptions
    pos_tagging : PosTaggingOptions
    ner : NerOptions
    fnr : FnrOptions
    srl : SrlOptions
    syntactic_parsing : SyntacticParsingOptions

    enable_additional_rule : Bool
  end

  enum TokenType
    Basic  = 0
    Number = 1
    Punct  = 2
  end

  struct NluToken
    str : String
    offset : UInt32
    type : UInt32
  end

  struct NluTokenArray
    size : UInt32
    items : NluToken*
  end

  struct NluTerm
    str : String    # term string
    offset : UInt32 # offset (character-level) in the text
    len : UInt32    # length (number of characters)
    start_token : UInt32
    token_count : UInt32
    freq : UInt32
    tag : String # part-of-speech tag
    tag_id : UInt32
  end

  struct NluTermArray
    size : UInt32
    items : NluTerm*
  end

  struct NluEntityType
    name : String
    i18n : String
    flag : UInt32
    path : String
  end

  struct NluEntityTypeArray
    size : UInt32
    items : NluEntityType*
  end

  struct NluEntity
    str : String    # entity string
    offset : UInt32 # offset (character-level) in the text
    len : UInt32    # length (number of characters)
    start_token : UInt32
    token_count : UInt32
    type : NluEntityType
    alt_types : NluEntityTypeArray
    meaning : String # semantic meaning of this entity in the current context
  end

  struct NluEntityArray
    size : UInt32
    items : NluEntity*
  end

  alias NluEngineHandle = Void*
  alias NluOutputHandle = Void*
  alias NluTermHandle = Void*

  fun create_engine = Nlu_CreateEngine(data_dir : CStr, worker_count : Int32) : NluEngineHandle
  fun destroy_engine = Nlu_DestroyEngine(engine_handle : NluEngineHandle) : Void

  fun init_options = Nlu_InitOptions(opt : NluOptions) : Void

  fun parse_text = Nlu_ParseText(engine_handle : NluEngineHandle, str : String, len : Int32) : NluOutputHandle
  fun parse_utf8_text = Nlu_ParseUtf8Text(engine_handle : NluEngineHandle, str : CStr, len : Int32) : NluOutputHandle
  fun parse_text_ext = Nlu_ParseTextExt(engine_handle : NluEngineHandle, str : String, len : Int32, options : String) : NluOutputHandle
  fun parse_utf8_text_ext = Nlu_ParseUtf8TextExt(engine_handle : NluEngineHandle, str : CStr, len : Int32, options : CStr) : NluOutputHandle
  fun destroy_output = Nlu_DestroyOutput(output_handle : NluOutputHandle)

  fun get_tokens = Nlu_GetTokens(output_handle : NluOutputHandle) : NluTokenArray
  fun get_words = Nlu_GetWords(output_handle : NluOutputHandle) : NluTermArray
  fun get_phrases = Nlu_GetPhrases(output_handle : NluOutputHandle) : NluTermArray
  fun get_entities = Nlu_GetEntities(output_handle : NluOutputHandle) : NluEntityArray
end
