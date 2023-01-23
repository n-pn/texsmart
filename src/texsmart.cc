#include <codecvt>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <locale>
#include <sstream>
#include <string>

#include "texsmart_nlu_api.h"
#include "texsmart_util.h"

using namespace std;
using namespace tencent::ai::texsmart;

std::string get_env(std::string const &key) {
  char *val = getenv(key.c_str());
  return val == NULL ? std::string("") : std::string(val);
}

std::wstring read_utf8_file(const char *filename) {
  std::wifstream wif(filename);
  wif.imbue(std::locale(wif.getloc(), new std::codecvt_utf8<wchar_t>));
  std::wstringstream wss;
  wss << wif.rdbuf();
  return wss.str();
}

bool extract(const string &data_dir, int worker_count, const wstring &input) {
  cout << "Starting NLU engine with worker_count: " << worker_count << endl;

  NluEngine engine;
  bool ret = engine.Init(data_dir.c_str(), worker_count);

  if (!ret) {
    cout << "Failed to initialize the NLU engine" << endl;
    return false;
  }

  cout << "NLU engine started! Parsing data..." << endl;

  NluOutput output;

  std::wstringstream wss(input);
  std::wstring line;

  std::wstring_convert<std::codecvt_utf8<wchar_t>> utf8_conv;
  ofstream out_words("output/words.tsv");
  ofstream out_phrases("output/phrases.tsv");
  ofstream out_entities("output/entities.tsv");

  NluOptions opt;

  opt.word_seg.location_as_one_word = true;
  opt.word_seg.person_as_one_word = true;
  opt.word_seg.organization_as_one_word = true;

  // opt.pos_tagging.alg = L"CRF";

  opt.ner.alg = L"fine.std";
  opt.ner.enable_deep_learning = true;
  opt.ner.enable_ne_adjustment = true;
  opt.ner.enable_fine_grained_ner = true;
  opt.ner.enable_deep_representation = true;

  opt.fnr.enable = false;
  opt.srl.enable = false;

  int line_count = 0;

  while (std::getline(wss, line)) {
    line_count++;
    if (line_count % 100 == 0) {
      cout << "- Parsing line: " << line_count << endl;
    }

    out_words << utf8_conv.to_bytes(line) << endl;
    out_phrases << utf8_conv.to_bytes(line) << endl;
    out_entities << utf8_conv.to_bytes(line) << endl;

    ret = engine.ParseText(output, line.c_str(), (int)line.size(), opt);

    if (!ret) {
      cout << "Error occurred in parsing text" << endl;
      out_words.close();
      out_phrases.close();
      out_entities.close();

      return false;
    }

    // save word level segmentation

    NluTermArray term_list = output.GetWords();
    for (uint32_t idx = 0; idx < term_list.size; idx++) {
      const auto &term = term_list.items[idx];

      out_words << utf8_conv.to_bytes(term.str) << '\t';
      out_words << utf8_conv.to_bytes(term.tag) << '\t';
      out_words << term.freq << endl;
    }
    out_words << endl;

    // save phrase level segmentation

    term_list = output.GetPhrases();
    for (uint32_t idx = 0; idx < term_list.size; idx++) {
      const auto &term = term_list.items[idx];

      out_phrases << utf8_conv.to_bytes(term.str) << '\t';
      out_phrases << utf8_conv.to_bytes(term.tag) << '\t';
      out_phrases << term.freq << endl;
    }
    out_phrases << endl;

    // save entities

    NluEntityArray entity_list = output.GetEntities();
    for (uint32_t idx = 0; idx < entity_list.size; idx++) {
      const auto &entity = entity_list.items[idx];

      out_entities << utf8_conv.to_bytes(entity.str);
      out_entities << '\t' << entity.offset;

      // english entity name:
      out_entities << '\t' << utf8_conv.to_bytes(entity.type.name);

      // chinese entity name:
      // out_entities << '\t' << utf8_conv.to_bytes(entity.type.i18n) ;

      // don't know, but since it is entity type it should be omitable
      // out_entities << '\t' << entity.type.flag ;

      // entity path (can be safely ignored because it exists in other file)
      // out_entities << '\t' << utf8_conv.to_bytes(entity.type.path) ;

      // related words, etc.
      // out_entities << '\t' << utf8_conv.to_bytes(entity.meaning) ;

      out_entities << endl;
    }

    out_entities << endl;
  }

  out_words.close();
  out_phrases.close();
  out_entities.close();

  return true;
}

int main(int argc, const char *argv[]) {
  std::string data_dir = get_env("DATA");

  if (data_dir.empty()) {
    data_dir = "./data/nlu/kb/";
  }

  int worker_count = 4;
  std::string workers_env = get_env("WORKERS");

  if (!workers_env.empty()) {
    worker_count = stoi(workers_env, nullptr, 10);
  }

  std::wstring content = read_utf8_file(argv[1]);

  bool ret = extract(data_dir, worker_count, content);
  return ret ? 0 : -1;
}
