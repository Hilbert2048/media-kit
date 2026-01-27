import 'package:uri_parser/uri_parser.dart';

void main() {
  String addPrefix(String path) {
    // Mock implementation
    return path;
  }

  String _sanitizeUri(String uri) {
    // Append \\?\ prefix on Windows to support long file paths.
    final parser = URIParser(uri);
    switch (parser.type) {
      case URIType.file:
        return addPrefix(parser.file!.path);
      case URIType.directory:
        return addPrefix(parser.directory!.path);
      case URIType.network:
        return parser.uri!.toString();
      default:
        return uri;
    }
  }

  var urls = [
    'http://example.com/foo%20bar',
    'http://example.com/foo bar',
    'https://example.com/path?query=value',
    'file:///path/to/file%20name.mp4',
    'http://192.168.1.1/video.mp4',
    'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/73/77/35606167773/35606167773-1-16.mp4?e=ig8euxZM2rNcNbRVhwdVhwdlhWdVhwdVhoNvNC8BqJIzNbfq9rVEuxTEnE8L5F6VnEsSTx0vkX8fqJeYTj_lta53NCM=&deadline=1769484182&nbs=1&os=akam&mid=0&platform=html5&gen=playurlv3&og=hw&oi=1805342631&trid=66382de0a3654fd8a999bbfbed61d52h&uipk=5&upsig=6d63ff03e4706564a5046170d01c0544&uparams=e,deadline,nbs,os,mid,platform,gen,og,oi,trid,uipk&hdnts=exp=1769484182~hmac=97641f897a17e55852f356ffe0b5b757ca30381e981477b1ebf376fec1a035f4&bvc=vod&nettype=0&bw=478822&dl=0&f=h_0_0&agrr=1&buvid=&build=0&orderid=0,1',
  ];

  for (var url in urls) {
    var sanitized = _sanitizeUri(url);
    print("Match: ${url == sanitized}");
    if (url != sanitized) {
      print("Original: '$url'");
      print("Sanitized: '$sanitized'");
    }
  }
}
