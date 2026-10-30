import 'package:flutter_test/flutter_test.dart';
import 'package:sunoh/api/art_urls.dart';

void main() {
  // Every case below is a URL taken verbatim from a live InnerTube response,
  // and every expected size was confirmed by fetching it.
  test('playlist track rows stop being 400px video frames', () {
    final (url, w, h) = upscaleArtUrl(
      'https://i.ytimg.com/vi/J_d_Q3pTYcc/hqdefault.jpg'
      '?sqp=-oaymwEWCJADEOEBIAQqCggAEOADGC0guwJIWg&rs=AMzJL3lU_qE',
      400,
      225,
    );
    expect(url, 'https://i.ytimg.com/vi/J_d_Q3pTYcc/maxresdefault.jpg');
    expect((w, h), (1280, 720));
  });

  test('the signed crop query is dropped, not carried to a new rendition', () {
    final (url, _, _) = upscaleArtUrl(
      'https://i.ytimg.com/vi/abc123XYZ_-/hqdefault.jpg?sqp=xx&rs=yy',
      400,
      225,
    );
    expect(url, isNot(contains('sqp')));
  });

  test('artist avatars survive the -c- crop marker', () {
    final (url, w, h) = upscaleArtUrl(
      'https://yt3.googleusercontent.com/ytc/AIdro_mRfA=w60-c-h60-k-c0x00ffffff-no-l90',
      60,
      60,
    );
    expect(
      url,
      'https://yt3.googleusercontent.com/ytc/AIdro_mRfA'
          '=w1200-c-h1200-k-c0x00ffffff-no-l90',
    );
    expect((w, h), (1200, 1200));
  });

  test('album headers keep their trailing modifiers', () {
    final (url, w, _) = upscaleArtUrl(
      'https://yt3.googleusercontent.com/eLoQKzsk=w544-h544-l90-rj',
      544,
      544,
    );
    expect(url, endsWith('=w1200-h1200-l90-rj'));
    expect(w, 1200);
  });

  test('=s shorthand still works', () {
    expect(upscaleArtUrl('https://lh3.googleusercontent.com/x=s576', 576, 576).$1,
        endsWith('=s1200'));
  });

  test('a wide banner is not squared into a portrait crop', () {
    final (_, w, h) = upscaleArtUrl(
      'https://yt3.googleusercontent.com/x=w1060-h175-p-l90',
      1060,
      175,
    );
    expect((w, h), (1200, 198));
  });

  test('rewriting is idempotent', () {
    final once = upscaleArtUrl('https://i.ytimg.com/vi/J_d_Q3pTYcc/hqdefault.jpg', 400, 225).$1;
    expect(upscaleArtUrl(once, 1280, 720).$1, once);
  });

  test('only ytimg gets a fallback chain', () {
    expect(
      artUrlChain('https://i.ytimg.com/vi/J_d_Q3pTYcc/maxresdefault.jpg'),
      [
        'https://i.ytimg.com/vi/J_d_Q3pTYcc/maxresdefault.jpg',
        'https://i.ytimg.com/vi/J_d_Q3pTYcc/sddefault.jpg',
        'https://i.ytimg.com/vi/J_d_Q3pTYcc/hqdefault.jpg',
      ],
    );
    expect(artUrlChain('https://yt3.googleusercontent.com/x=w1200-h1200-l90').length, 1);
  });

  test('a chain never repeats the url it starts from', () {
    final chain = artUrlChain('https://i.ytimg.com/vi/J_d_Q3pTYcc/hqdefault.jpg');
    expect(chain.toSet().length, chain.length);
  });

  test('unknown hosts pass through untouched', () {
    expect(upscaleArtUrl('https://c.saavncdn.com/x_500x500.jpg', 500, 500).$1,
        'https://c.saavncdn.com/x_500x500.jpg');
  });

  test('Apple podcast art is asked for at 1200 and keeps its crop mode', () {
    final (url, w, h) = upscaleArtUrl(
      'https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/cd/ef/x.jpg/600x600bb.jpg',
      null,
      null,
    );
    expect(url, endsWith('/x.jpg/1200x1200bb.jpg'));
    expect((w, h), (1200, 1200));
  });
}
