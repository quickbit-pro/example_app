// Country names use CLDR region labels (Intl.DisplayNames).
// Getter coverage matches flutter_country_selector's country interface.
part of 'phone_localizations.dart';

class _AppCountryNames extends CountrySelectorLocalizationEn {
  _AppCountryNames(this.app, this.names) : super(app.locale.languageCode);
  final AppLocalizations app;
  final Map<String, String> names;

  @override
  String get noResultMessage => app.translate('No results');
  @override
  String get search => app.translate('Search');
  @override
  String get typeToSearch => app.translate('Search countries');
  @override
  String selectCountry(String country) =>
      app.translate('Select {p0}', {'p0': country});

  @override
  String get ac_ => names['AC']!;
  @override
  String get ad_ => names['AD']!;
  @override
  String get ae_ => names['AE']!;
  @override
  String get af_ => names['AF']!;
  @override
  String get ag_ => names['AG']!;
  @override
  String get ai_ => names['AI']!;
  @override
  String get al_ => names['AL']!;
  @override
  String get am_ => names['AM']!;
  @override
  String get an_ => names['AN']!;
  @override
  String get ao_ => names['AO']!;
  @override
  String get aq_ => names['AQ']!;
  @override
  String get ar_ => names['AR']!;
  @override
  String get as_ => names['AS']!;
  @override
  String get at_ => names['AT']!;
  @override
  String get au_ => names['AU']!;
  @override
  String get aw_ => names['AW']!;
  @override
  String get ax_ => names['AX']!;
  @override
  String get az_ => names['AZ']!;
  @override
  String get ba_ => names['BA']!;
  @override
  String get bb_ => names['BB']!;
  @override
  String get bd_ => names['BD']!;
  @override
  String get be_ => names['BE']!;
  @override
  String get bf_ => names['BF']!;
  @override
  String get bg_ => names['BG']!;
  @override
  String get bh_ => names['BH']!;
  @override
  String get bi_ => names['BI']!;
  @override
  String get bj_ => names['BJ']!;
  @override
  String get bl_ => names['BL']!;
  @override
  String get bm_ => names['BM']!;
  @override
  String get bn_ => names['BN']!;
  @override
  String get bo_ => names['BO']!;
  @override
  String get bq_ => names['BQ']!;
  @override
  String get br_ => names['BR']!;
  @override
  String get bs_ => names['BS']!;
  @override
  String get bt_ => names['BT']!;
  @override
  String get bw_ => names['BW']!;
  @override
  String get by_ => names['BY']!;
  @override
  String get bz_ => names['BZ']!;
  @override
  String get ca_ => names['CA']!;
  @override
  String get cc_ => names['CC']!;
  @override
  String get cd_ => names['CD']!;
  @override
  String get cf_ => names['CF']!;
  @override
  String get cg_ => names['CG']!;
  @override
  String get ch_ => names['CH']!;
  @override
  String get ci_ => names['CI']!;
  @override
  String get ck_ => names['CK']!;
  @override
  String get cl_ => names['CL']!;
  @override
  String get cm_ => names['CM']!;
  @override
  String get cn_ => names['CN']!;
  @override
  String get co_ => names['CO']!;
  @override
  String get cr_ => names['CR']!;
  @override
  String get cu_ => names['CU']!;
  @override
  String get cv_ => names['CV']!;
  @override
  String get cw_ => names['CW']!;
  @override
  String get cx_ => names['CX']!;
  @override
  String get cy_ => names['CY']!;
  @override
  String get cz_ => names['CZ']!;
  @override
  String get de_ => names['DE']!;
  @override
  String get dj_ => names['DJ']!;
  @override
  String get dk_ => names['DK']!;
  @override
  String get dm_ => names['DM']!;
  @override
  String get do_ => names['DO']!;
  @override
  String get dz_ => names['DZ']!;
  @override
  String get ec_ => names['EC']!;
  @override
  String get ee_ => names['EE']!;
  @override
  String get eg_ => names['EG']!;
  @override
  String get eh_ => names['EH']!;
  @override
  String get er_ => names['ER']!;
  @override
  String get es_ => names['ES']!;
  @override
  String get et_ => names['ET']!;
  @override
  String get fi_ => names['FI']!;
  @override
  String get fj_ => names['FJ']!;
  @override
  String get fk_ => names['FK']!;
  @override
  String get fm_ => names['FM']!;
  @override
  String get fo_ => names['FO']!;
  @override
  String get fr_ => names['FR']!;
  @override
  String get ga_ => names['GA']!;
  @override
  String get gb_ => names['GB']!;
  @override
  String get gd_ => names['GD']!;
  @override
  String get ge_ => names['GE']!;
  @override
  String get gf_ => names['GF']!;
  @override
  String get gg_ => names['GG']!;
  @override
  String get gh_ => names['GH']!;
  @override
  String get gi_ => names['GI']!;
  @override
  String get gl_ => names['GL']!;
  @override
  String get gm_ => names['GM']!;
  @override
  String get gn_ => names['GN']!;
  @override
  String get gp_ => names['GP']!;
  @override
  String get gq_ => names['GQ']!;
  @override
  String get gr_ => names['GR']!;
  @override
  String get gs_ => names['GS']!;
  @override
  String get gt_ => names['GT']!;
  @override
  String get gu_ => names['GU']!;
  @override
  String get gw_ => names['GW']!;
  @override
  String get gy_ => names['GY']!;
  @override
  String get hk_ => names['HK']!;
  @override
  String get hn_ => names['HN']!;
  @override
  String get hr_ => names['HR']!;
  @override
  String get ht_ => names['HT']!;
  @override
  String get hu_ => names['HU']!;
  @override
  String get id_ => names['ID']!;
  @override
  String get ie_ => names['IE']!;
  @override
  String get il_ => names['IL']!;
  @override
  String get im_ => names['IM']!;
  @override
  String get in_ => names['IN']!;
  @override
  String get io_ => names['IO']!;
  @override
  String get iq_ => names['IQ']!;
  @override
  String get ir_ => names['IR']!;
  @override
  String get is_ => names['IS']!;
  @override
  String get it_ => names['IT']!;
  @override
  String get je_ => names['JE']!;
  @override
  String get jm_ => names['JM']!;
  @override
  String get jo_ => names['JO']!;
  @override
  String get jp_ => names['JP']!;
  @override
  String get ke_ => names['KE']!;
  @override
  String get kg_ => names['KG']!;
  @override
  String get kh_ => names['KH']!;
  @override
  String get ki_ => names['KI']!;
  @override
  String get km_ => names['KM']!;
  @override
  String get kn_ => names['KN']!;
  @override
  String get kp_ => names['KP']!;
  @override
  String get kr_ => names['KR']!;
  @override
  String get kw_ => names['KW']!;
  @override
  String get ky_ => names['KY']!;
  @override
  String get kz_ => names['KZ']!;
  @override
  String get la_ => names['LA']!;
  @override
  String get lb_ => names['LB']!;
  @override
  String get lc_ => names['LC']!;
  @override
  String get li_ => names['LI']!;
  @override
  String get lk_ => names['LK']!;
  @override
  String get lr_ => names['LR']!;
  @override
  String get ls_ => names['LS']!;
  @override
  String get lt_ => names['LT']!;
  @override
  String get lu_ => names['LU']!;
  @override
  String get lv_ => names['LV']!;
  @override
  String get ly_ => names['LY']!;
  @override
  String get ma_ => names['MA']!;
  @override
  String get mc_ => names['MC']!;
  @override
  String get md_ => names['MD']!;
  @override
  String get me_ => names['ME']!;
  @override
  String get mf_ => names['MF']!;
  @override
  String get mg_ => names['MG']!;
  @override
  String get mh_ => names['MH']!;
  @override
  String get mk_ => names['MK']!;
  @override
  String get ml_ => names['ML']!;
  @override
  String get mm_ => names['MM']!;
  @override
  String get mn_ => names['MN']!;
  @override
  String get mo_ => names['MO']!;
  @override
  String get mp_ => names['MP']!;
  @override
  String get mq_ => names['MQ']!;
  @override
  String get mr_ => names['MR']!;
  @override
  String get ms_ => names['MS']!;
  @override
  String get mt_ => names['MT']!;
  @override
  String get mu_ => names['MU']!;
  @override
  String get mv_ => names['MV']!;
  @override
  String get mw_ => names['MW']!;
  @override
  String get mx_ => names['MX']!;
  @override
  String get my_ => names['MY']!;
  @override
  String get mz_ => names['MZ']!;
  @override
  String get na_ => names['NA']!;
  @override
  String get nc_ => names['NC']!;
  @override
  String get ne_ => names['NE']!;
  @override
  String get nf_ => names['NF']!;
  @override
  String get ng_ => names['NG']!;
  @override
  String get ni_ => names['NI']!;
  @override
  String get nl_ => names['NL']!;
  @override
  String get no_ => names['NO']!;
  @override
  String get np_ => names['NP']!;
  @override
  String get nr_ => names['NR']!;
  @override
  String get nu_ => names['NU']!;
  @override
  String get nz_ => names['NZ']!;
  @override
  String get om_ => names['OM']!;
  @override
  String get pa_ => names['PA']!;
  @override
  String get pe_ => names['PE']!;
  @override
  String get pf_ => names['PF']!;
  @override
  String get pg_ => names['PG']!;
  @override
  String get ph_ => names['PH']!;
  @override
  String get pk_ => names['PK']!;
  @override
  String get pl_ => names['PL']!;
  @override
  String get pm_ => names['PM']!;
  @override
  String get pn_ => names['PN']!;
  @override
  String get pr_ => names['PR']!;
  @override
  String get ps_ => names['PS']!;
  @override
  String get pt_ => names['PT']!;
  @override
  String get pw_ => names['PW']!;
  @override
  String get py_ => names['PY']!;
  @override
  String get qa_ => names['QA']!;
  @override
  String get re_ => names['RE']!;
  @override
  String get ro_ => names['RO']!;
  @override
  String get rs_ => names['RS']!;
  @override
  String get ru_ => names['RU']!;
  @override
  String get rw_ => names['RW']!;
  @override
  String get sa_ => names['SA']!;
  @override
  String get sb_ => names['SB']!;
  @override
  String get sc_ => names['SC']!;
  @override
  String get sd_ => names['SD']!;
  @override
  String get se_ => names['SE']!;
  @override
  String get sg_ => names['SG']!;
  @override
  String get sh_ => names['SH']!;
  @override
  String get si_ => names['SI']!;
  @override
  String get sj_ => names['SJ']!;
  @override
  String get sk_ => names['SK']!;
  @override
  String get sl_ => names['SL']!;
  @override
  String get sm_ => names['SM']!;
  @override
  String get sn_ => names['SN']!;
  @override
  String get so_ => names['SO']!;
  @override
  String get sr_ => names['SR']!;
  @override
  String get ss_ => names['SS']!;
  @override
  String get st_ => names['ST']!;
  @override
  String get sv_ => names['SV']!;
  @override
  String get sx_ => names['SX']!;
  @override
  String get sy_ => names['SY']!;
  @override
  String get sz_ => names['SZ']!;
  @override
  String get ta_ => names['TA']!;
  @override
  String get tc_ => names['TC']!;
  @override
  String get td_ => names['TD']!;
  @override
  String get tg_ => names['TG']!;
  @override
  String get th_ => names['TH']!;
  @override
  String get tj_ => names['TJ']!;
  @override
  String get tk_ => names['TK']!;
  @override
  String get tl_ => names['TL']!;
  @override
  String get tm_ => names['TM']!;
  @override
  String get tn_ => names['TN']!;
  @override
  String get to_ => names['TO']!;
  @override
  String get tr_ => names['TR']!;
  @override
  String get tt_ => names['TT']!;
  @override
  String get tv_ => names['TV']!;
  @override
  String get tw_ => names['TW']!;
  @override
  String get tz_ => names['TZ']!;
  @override
  String get ua_ => names['UA']!;
  @override
  String get ug_ => names['UG']!;
  @override
  String get us_ => names['US']!;
  @override
  String get uy_ => names['UY']!;
  @override
  String get uz_ => names['UZ']!;
  @override
  String get va_ => names['VA']!;
  @override
  String get vc_ => names['VC']!;
  @override
  String get ve_ => names['VE']!;
  @override
  String get vg_ => names['VG']!;
  @override
  String get vi_ => names['VI']!;
  @override
  String get vn_ => names['VN']!;
  @override
  String get vu_ => names['VU']!;
  @override
  String get wf_ => names['WF']!;
  @override
  String get ws_ => names['WS']!;
  @override
  String get xk_ => names['XK']!;
  @override
  String get ye_ => names['YE']!;
  @override
  String get yt_ => names['YT']!;
  @override
  String get za_ => names['ZA']!;
  @override
  String get zm_ => names['ZM']!;
  @override
  String get zw_ => names['ZW']!;
}

// Bundled in code so country selection works before language assets are cached.
const _countryNames = <String, Map<String, String>>{
  'ja': {
    'AC': 'アセンション島',
    'AD': 'アンドラ',
    'AE': 'アラブ首長国連邦',
    'AF': 'アフガニスタン',
    'AG': 'アンティグア・バーブーダ',
    'AI': 'アンギラ',
    'AL': 'アルバニア',
    'AM': 'アルメニア',
    'AN': 'キュラソー',
    'AO': 'アンゴラ',
    'AQ': '南極',
    'AR': 'アルゼンチン',
    'AS': '米領サモア',
    'AT': 'オーストリア',
    'AU': 'オーストラリア',
    'AW': 'アルバ',
    'AX': 'オーランド諸島',
    'AZ': 'アゼルバイジャン',
    'BA': 'ボスニア・ヘルツェゴビナ',
    'BB': 'バルバドス',
    'BD': 'バングラデシュ',
    'BE': 'ベルギー',
    'BF': 'ブルキナファソ',
    'BG': 'ブルガリア',
    'BH': 'バーレーン',
    'BI': 'ブルンジ',
    'BJ': 'ベナン',
    'BL': 'サン・バルテルミー',
    'BM': 'バミューダ',
    'BN': 'ブルネイ',
    'BO': 'ボリビア',
    'BQ': 'オランダ領カリブ',
    'BR': 'ブラジル',
    'BS': 'バハマ',
    'BT': 'ブータン',
    'BW': 'ボツワナ',
    'BY': 'ベラルーシ',
    'BZ': 'ベリーズ',
    'CA': 'カナダ',
    'CC': 'ココス(キーリング)諸島',
    'CD': 'コンゴ民主共和国(キンシャサ)',
    'CF': '中央アフリカ共和国',
    'CG': 'コンゴ共和国(ブラザビル)',
    'CH': 'スイス',
    'CI': 'コートジボワール',
    'CK': 'クック諸島',
    'CL': 'チリ',
    'CM': 'カメルーン',
    'CN': '中国',
    'CO': 'コロンビア',
    'CR': 'コスタリカ',
    'CU': 'キューバ',
    'CV': 'カーボベルデ',
    'CW': 'キュラソー',
    'CX': 'クリスマス島',
    'CY': 'キプロス',
    'CZ': 'チェコ',
    'DE': 'ドイツ',
    'DJ': 'ジブチ',
    'DK': 'デンマーク',
    'DM': 'ドミニカ国',
    'DO': 'ドミニカ共和国',
    'DZ': 'アルジェリア',
    'EC': 'エクアドル',
    'EE': 'エストニア',
    'EG': 'エジプト',
    'EH': '西サハラ',
    'ER': 'エリトリア',
    'ES': 'スペイン',
    'ET': 'エチオピア',
    'FI': 'フィンランド',
    'FJ': 'フィジー',
    'FK': 'フォークランド諸島',
    'FM': 'ミクロネシア連邦',
    'FO': 'フェロー諸島',
    'FR': 'フランス',
    'GA': 'ガボン',
    'GB': 'イギリス',
    'GD': 'グレナダ',
    'GE': 'ジョージア',
    'GF': '仏領ギアナ',
    'GG': 'ガーンジー',
    'GH': 'ガーナ',
    'GI': 'ジブラルタル',
    'GL': 'グリーンランド',
    'GM': 'ガンビア',
    'GN': 'ギニア',
    'GP': 'グアドループ',
    'GQ': '赤道ギニア',
    'GR': 'ギリシャ',
    'GS': 'サウスジョージア・サウスサンドウィッチ諸島',
    'GT': 'グアテマラ',
    'GU': 'グアム',
    'GW': 'ギニアビサウ',
    'GY': 'ガイアナ',
    'HK': '中華人民共和国香港特別行政区',
    'HN': 'ホンジュラス',
    'HR': 'クロアチア',
    'HT': 'ハイチ',
    'HU': 'ハンガリー',
    'ID': 'インドネシア',
    'IE': 'アイルランド',
    'IL': 'イスラエル',
    'IM': 'マン島',
    'IN': 'インド',
    'IO': '英領インド洋地域',
    'IQ': 'イラク',
    'IR': 'イラン',
    'IS': 'アイスランド',
    'IT': 'イタリア',
    'JE': 'ジャージー',
    'JM': 'ジャマイカ',
    'JO': 'ヨルダン',
    'JP': '日本',
    'KE': 'ケニア',
    'KG': 'キルギス',
    'KH': 'カンボジア',
    'KI': 'キリバス',
    'KM': 'コモロ',
    'KN': 'セントクリストファー・ネーヴィス',
    'KP': '北朝鮮',
    'KR': '韓国',
    'KW': 'クウェート',
    'KY': 'ケイマン諸島',
    'KZ': 'カザフスタン',
    'LA': 'ラオス',
    'LB': 'レバノン',
    'LC': 'セントルシア',
    'LI': 'リヒテンシュタイン',
    'LK': 'スリランカ',
    'LR': 'リベリア',
    'LS': 'レソト',
    'LT': 'リトアニア',
    'LU': 'ルクセンブルク',
    'LV': 'ラトビア',
    'LY': 'リビア',
    'MA': 'モロッコ',
    'MC': 'モナコ',
    'MD': 'モルドバ',
    'ME': 'モンテネグロ',
    'MF': 'サン・マルタン',
    'MG': 'マダガスカル',
    'MH': 'マーシャル諸島',
    'MK': '北マケドニア',
    'ML': 'マリ',
    'MM': 'ミャンマー (ビルマ)',
    'MN': 'モンゴル',
    'MO': '中華人民共和国マカオ特別行政区',
    'MP': '北マリアナ諸島',
    'MQ': 'マルティニーク',
    'MR': 'モーリタニア',
    'MS': 'モントセラト',
    'MT': 'マルタ',
    'MU': 'モーリシャス',
    'MV': 'モルディブ',
    'MW': 'マラウイ',
    'MX': 'メキシコ',
    'MY': 'マレーシア',
    'MZ': 'モザンビーク',
    'NA': 'ナミビア',
    'NC': 'ニューカレドニア',
    'NE': 'ニジェール',
    'NF': 'ノーフォーク島',
    'NG': 'ナイジェリア',
    'NI': 'ニカラグア',
    'NL': 'オランダ',
    'NO': 'ノルウェー',
    'NP': 'ネパール',
    'NR': 'ナウル',
    'NU': 'ニウエ',
    'NZ': 'ニュージーランド',
    'OM': 'オマーン',
    'PA': 'パナマ',
    'PE': 'ペルー',
    'PF': '仏領ポリネシア',
    'PG': 'パプアニューギニア',
    'PH': 'フィリピン',
    'PK': 'パキスタン',
    'PL': 'ポーランド',
    'PM': 'サンピエール島・ミクロン島',
    'PN': 'ピトケアン諸島',
    'PR': 'プエルトリコ',
    'PS': 'パレスチナ自治区',
    'PT': 'ポルトガル',
    'PW': 'パラオ',
    'PY': 'パラグアイ',
    'QA': 'カタール',
    'RE': 'レユニオン',
    'RO': 'ルーマニア',
    'RS': 'セルビア',
    'RU': 'ロシア',
    'RW': 'ルワンダ',
    'SA': 'サウジアラビア',
    'SB': 'ソロモン諸島',
    'SC': 'セーシェル',
    'SD': 'スーダン',
    'SE': 'スウェーデン',
    'SG': 'シンガポール',
    'SH': 'セントヘレナ',
    'SI': 'スロベニア',
    'SJ': 'スバールバル諸島・ヤンマイエン島',
    'SK': 'スロバキア',
    'SL': 'シエラレオネ',
    'SM': 'サンマリノ',
    'SN': 'セネガル',
    'SO': 'ソマリア',
    'SR': 'スリナム',
    'SS': '南スーダン',
    'ST': 'サントメ・プリンシペ',
    'SV': 'エルサルバドル',
    'SX': 'シント・マールテン',
    'SY': 'シリア',
    'SZ': 'エスワティニ',
    'TA': 'トリスタン・ダ・クーニャ',
    'TC': 'タークス・カイコス諸島',
    'TD': 'チャド',
    'TG': 'トーゴ',
    'TH': 'タイ',
    'TJ': 'タジキスタン',
    'TK': 'トケラウ',
    'TL': '東ティモール',
    'TM': 'トルクメニスタン',
    'TN': 'チュニジア',
    'TO': 'トンガ',
    'TR': 'トルコ',
    'TT': 'トリニダード・トバゴ',
    'TV': 'ツバル',
    'TW': '台湾',
    'TZ': 'タンザニア',
    'UA': 'ウクライナ',
    'UG': 'ウガンダ',
    'US': 'アメリカ合衆国',
    'UY': 'ウルグアイ',
    'UZ': 'ウズベキスタン',
    'VA': 'バチカン市国',
    'VC': 'セントビンセント及びグレナディーン諸島',
    'VE': 'ベネズエラ',
    'VG': '英領ヴァージン諸島',
    'VI': '米領ヴァージン諸島',
    'VN': 'ベトナム',
    'VU': 'バヌアツ',
    'WF': 'ウォリス・フツナ',
    'WS': 'サモア',
    'XK': 'コソボ',
    'YE': 'イエメン',
    'YT': 'マヨット',
    'ZA': '南アフリカ',
    'ZM': 'ザンビア',
    'ZW': 'ジンバブエ'
  },
  'id': {
    'AC': 'Pulau Ascension',
    'AD': 'Andorra',
    'AE': 'Uni Emirat Arab',
    'AF': 'Afganistan',
    'AG': 'Antigua dan Barbuda',
    'AI': 'Anguilla',
    'AL': 'Albania',
    'AM': 'Armenia',
    'AN': 'Curaçao',
    'AO': 'Angola',
    'AQ': 'Antarktika',
    'AR': 'Argentina',
    'AS': 'Samoa Amerika',
    'AT': 'Austria',
    'AU': 'Australia',
    'AW': 'Aruba',
    'AX': 'Kepulauan Aland',
    'AZ': 'Azerbaijan',
    'BA': 'Bosnia dan Herzegovina',
    'BB': 'Barbados',
    'BD': 'Bangladesh',
    'BE': 'Belgia',
    'BF': 'Burkina Faso',
    'BG': 'Bulgaria',
    'BH': 'Bahrain',
    'BI': 'Burundi',
    'BJ': 'Benin',
    'BL': 'Saint Barthélemy',
    'BM': 'Bermuda',
    'BN': 'Brunei',
    'BO': 'Bolivia',
    'BQ': 'Belanda Karibia',
    'BR': 'Brasil',
    'BS': 'Bahama',
    'BT': 'Bhutan',
    'BW': 'Botswana',
    'BY': 'Belarus',
    'BZ': 'Belize',
    'CA': 'Kanada',
    'CC': 'Kepulauan Cocos (Keeling)',
    'CD': 'Kongo - Kinshasa',
    'CF': 'Republik Afrika Tengah',
    'CG': 'Kongo - Brazzaville',
    'CH': 'Swiss',
    'CI': 'Côte d’Ivoire',
    'CK': 'Kepulauan Cook',
    'CL': 'Cile',
    'CM': 'Kamerun',
    'CN': 'Tiongkok',
    'CO': 'Kolombia',
    'CR': 'Kosta Rika',
    'CU': 'Kuba',
    'CV': 'Tanjung Verde',
    'CW': 'Curaçao',
    'CX': 'Pulau Natal',
    'CY': 'Siprus',
    'CZ': 'Ceko',
    'DE': 'Jerman',
    'DJ': 'Jibuti',
    'DK': 'Denmark',
    'DM': 'Dominika',
    'DO': 'Republik Dominika',
    'DZ': 'Aljazair',
    'EC': 'Ekuador',
    'EE': 'Estonia',
    'EG': 'Mesir',
    'EH': 'Sahara Barat',
    'ER': 'Eritrea',
    'ES': 'Spanyol',
    'ET': 'Etiopia',
    'FI': 'Finlandia',
    'FJ': 'Fiji',
    'FK': 'Kepulauan Falkland',
    'FM': 'Mikronesia',
    'FO': 'Kepulauan Faroe',
    'FR': 'Prancis',
    'GA': 'Gabon',
    'GB': 'Inggris Raya',
    'GD': 'Grenada',
    'GE': 'Georgia',
    'GF': 'Guyana Prancis',
    'GG': 'Guernsey',
    'GH': 'Ghana',
    'GI': 'Gibraltar',
    'GL': 'Greenland',
    'GM': 'Gambia',
    'GN': 'Guinea',
    'GP': 'Guadeloupe',
    'GQ': 'Guinea Ekuatorial',
    'GR': 'Yunani',
    'GS': 'Georgia Selatan & Kep. Sandwich Selatan',
    'GT': 'Guatemala',
    'GU': 'Guam',
    'GW': 'Guinea-Bissau',
    'GY': 'Guyana',
    'HK': 'Hong Kong DAK Tiongkok',
    'HN': 'Honduras',
    'HR': 'Kroasia',
    'HT': 'Haiti',
    'HU': 'Hungaria',
    'ID': 'Indonesia',
    'IE': 'Irlandia',
    'IL': 'Israel',
    'IM': 'Pulau Man',
    'IN': 'India',
    'IO': 'Wilayah Inggris di Samudra Hindia',
    'IQ': 'Irak',
    'IR': 'Iran',
    'IS': 'Islandia',
    'IT': 'Italia',
    'JE': 'Jersey',
    'JM': 'Jamaika',
    'JO': 'Yordania',
    'JP': 'Jepang',
    'KE': 'Kenya',
    'KG': 'Kirgizstan',
    'KH': 'Kamboja',
    'KI': 'Kiribati',
    'KM': 'Komoro',
    'KN': 'Saint Kitts dan Nevis',
    'KP': 'Korea Utara',
    'KR': 'Korea Selatan',
    'KW': 'Kuwait',
    'KY': 'Kepulauan Cayman',
    'KZ': 'Kazakhstan',
    'LA': 'Laos',
    'LB': 'Lebanon',
    'LC': 'Saint Lucia',
    'LI': 'Liechtenstein',
    'LK': 'Sri Lanka',
    'LR': 'Liberia',
    'LS': 'Lesotho',
    'LT': 'Lituania',
    'LU': 'Luksemburg',
    'LV': 'Latvia',
    'LY': 'Libya',
    'MA': 'Maroko',
    'MC': 'Monako',
    'MD': 'Moldova',
    'ME': 'Montenegro',
    'MF': 'Saint Martin',
    'MG': 'Madagaskar',
    'MH': 'Kepulauan Marshall',
    'MK': 'Makedonia Utara',
    'ML': 'Mali',
    'MM': 'Myanmar (Burma)',
    'MN': 'Mongolia',
    'MO': 'Makau DAK Tiongkok',
    'MP': 'Kepulauan Mariana Utara',
    'MQ': 'Martinik',
    'MR': 'Mauritania',
    'MS': 'Montserrat',
    'MT': 'Malta',
    'MU': 'Mauritius',
    'MV': 'Maladewa',
    'MW': 'Malawi',
    'MX': 'Meksiko',
    'MY': 'Malaysia',
    'MZ': 'Mozambik',
    'NA': 'Namibia',
    'NC': 'Kaledonia Baru',
    'NE': 'Niger',
    'NF': 'Kepulauan Norfolk',
    'NG': 'Nigeria',
    'NI': 'Nikaragua',
    'NL': 'Belanda',
    'NO': 'Norwegia',
    'NP': 'Nepal',
    'NR': 'Nauru',
    'NU': 'Niue',
    'NZ': 'Selandia Baru',
    'OM': 'Oman',
    'PA': 'Panama',
    'PE': 'Peru',
    'PF': 'Polinesia Prancis',
    'PG': 'Papua Nugini',
    'PH': 'Filipina',
    'PK': 'Pakistan',
    'PL': 'Polandia',
    'PM': 'Saint Pierre dan Miquelon',
    'PN': 'Kepulauan Pitcairn',
    'PR': 'Puerto Riko',
    'PS': 'Wilayah Palestina',
    'PT': 'Portugal',
    'PW': 'Palau',
    'PY': 'Paraguay',
    'QA': 'Qatar',
    'RE': 'Réunion',
    'RO': 'Rumania',
    'RS': 'Serbia',
    'RU': 'Rusia',
    'RW': 'Rwanda',
    'SA': 'Arab Saudi',
    'SB': 'Kepulauan Solomon',
    'SC': 'Seychelles',
    'SD': 'Sudan',
    'SE': 'Swedia',
    'SG': 'Singapura',
    'SH': 'Saint Helena',
    'SI': 'Slovenia',
    'SJ': 'Kepulauan Svalbard dan Jan Mayen',
    'SK': 'Slovakia',
    'SL': 'Sierra Leone',
    'SM': 'San Marino',
    'SN': 'Senegal',
    'SO': 'Somalia',
    'SR': 'Suriname',
    'SS': 'Sudan Selatan',
    'ST': 'Sao Tome dan Principe',
    'SV': 'El Salvador',
    'SX': 'Sint Maarten',
    'SY': 'Suriah',
    'SZ': 'eSwatini',
    'TA': 'Tristan da Cunha',
    'TC': 'Kepulauan Turks dan Caicos',
    'TD': 'Chad',
    'TG': 'Togo',
    'TH': 'Thailand',
    'TJ': 'Tajikistan',
    'TK': 'Tokelau',
    'TL': 'Timor Leste',
    'TM': 'Turkmenistan',
    'TN': 'Tunisia',
    'TO': 'Tonga',
    'TR': 'Turki',
    'TT': 'Trinidad dan Tobago',
    'TV': 'Tuvalu',
    'TW': 'Taiwan',
    'TZ': 'Tanzania',
    'UA': 'Ukraina',
    'UG': 'Uganda',
    'US': 'Amerika Serikat',
    'UY': 'Uruguay',
    'UZ': 'Uzbekistan',
    'VA': 'Vatikan',
    'VC': 'Saint Vincent dan Grenadine',
    'VE': 'Venezuela',
    'VG': 'Kepulauan Virgin Britania Raya',
    'VI': 'Kepulauan Virgin Amerika Serikat',
    'VN': 'Vietnam',
    'VU': 'Vanuatu',
    'WF': 'Kepulauan Wallis dan Futuna',
    'WS': 'Samoa',
    'XK': 'Kosovo',
    'YE': 'Yaman',
    'YT': 'Mayotte',
    'ZA': 'Afrika Selatan',
    'ZM': 'Zambia',
    'ZW': 'Zimbabwe'
  },
  'ko': {
    'AC': '어센션섬',
    'AD': '안도라',
    'AE': '아랍에미리트',
    'AF': '아프가니스탄',
    'AG': '앤티가 바부다',
    'AI': '앵귈라',
    'AL': '알바니아',
    'AM': '아르메니아',
    'AN': '퀴라소',
    'AO': '앙골라',
    'AQ': '남극 대륙',
    'AR': '아르헨티나',
    'AS': '아메리칸 사모아',
    'AT': '오스트리아',
    'AU': '오스트레일리아',
    'AW': '아루바',
    'AX': '올란드 제도',
    'AZ': '아제르바이잔',
    'BA': '보스니아 헤르체고비나',
    'BB': '바베이도스',
    'BD': '방글라데시',
    'BE': '벨기에',
    'BF': '부르키나파소',
    'BG': '불가리아',
    'BH': '바레인',
    'BI': '부룬디',
    'BJ': '베냉',
    'BL': '생바르텔레미',
    'BM': '버뮤다',
    'BN': '브루나이',
    'BO': '볼리비아',
    'BQ': '네덜란드령 카리브',
    'BR': '브라질',
    'BS': '바하마',
    'BT': '부탄',
    'BW': '보츠와나',
    'BY': '벨라루스',
    'BZ': '벨리즈',
    'CA': '캐나다',
    'CC': '코코스 제도',
    'CD': '콩고-킨샤사',
    'CF': '중앙 아프리카 공화국',
    'CG': '콩고-브라자빌',
    'CH': '스위스',
    'CI': '코트디부아르',
    'CK': '쿡 제도',
    'CL': '칠레',
    'CM': '카메룬',
    'CN': '중국',
    'CO': '콜롬비아',
    'CR': '코스타리카',
    'CU': '쿠바',
    'CV': '카보베르데',
    'CW': '퀴라소',
    'CX': '크리스마스섬',
    'CY': '키프로스',
    'CZ': '체코',
    'DE': '독일',
    'DJ': '지부티',
    'DK': '덴마크',
    'DM': '도미니카',
    'DO': '도미니카 공화국',
    'DZ': '알제리',
    'EC': '에콰도르',
    'EE': '에스토니아',
    'EG': '이집트',
    'EH': '서사하라',
    'ER': '에리트리아',
    'ES': '스페인',
    'ET': '에티오피아',
    'FI': '핀란드',
    'FJ': '피지',
    'FK': '포클랜드 제도',
    'FM': '미크로네시아',
    'FO': '페로 제도',
    'FR': '프랑스',
    'GA': '가봉',
    'GB': '영국',
    'GD': '그레나다',
    'GE': '조지아',
    'GF': '프랑스령 기아나',
    'GG': '건지',
    'GH': '가나',
    'GI': '지브롤터',
    'GL': '그린란드',
    'GM': '감비아',
    'GN': '기니',
    'GP': '과들루프',
    'GQ': '적도 기니',
    'GR': '그리스',
    'GS': '사우스조지아 사우스샌드위치 제도',
    'GT': '과테말라',
    'GU': '괌',
    'GW': '기니비사우',
    'GY': '가이아나',
    'HK': '홍콩(중국 특별행정구)',
    'HN': '온두라스',
    'HR': '크로아티아',
    'HT': '아이티',
    'HU': '헝가리',
    'ID': '인도네시아',
    'IE': '아일랜드',
    'IL': '이스라엘',
    'IM': '맨섬',
    'IN': '인도',
    'IO': '영국령 인도양 지역',
    'IQ': '이라크',
    'IR': '이란',
    'IS': '아이슬란드',
    'IT': '이탈리아',
    'JE': '저지',
    'JM': '자메이카',
    'JO': '요르단',
    'JP': '일본',
    'KE': '케냐',
    'KG': '키르기스스탄',
    'KH': '캄보디아',
    'KI': '키리바시',
    'KM': '코모로',
    'KN': '세인트키츠 네비스',
    'KP': '북한',
    'KR': '대한민국',
    'KW': '쿠웨이트',
    'KY': '케이맨 제도',
    'KZ': '카자흐스탄',
    'LA': '라오스',
    'LB': '레바논',
    'LC': '세인트루시아',
    'LI': '리히텐슈타인',
    'LK': '스리랑카',
    'LR': '라이베리아',
    'LS': '레소토',
    'LT': '리투아니아',
    'LU': '룩셈부르크',
    'LV': '라트비아',
    'LY': '리비아',
    'MA': '모로코',
    'MC': '모나코',
    'MD': '몰도바',
    'ME': '몬테네그로',
    'MF': '생마르탱',
    'MG': '마다가스카르',
    'MH': '마셜 제도',
    'MK': '북마케도니아',
    'ML': '말리',
    'MM': '미얀마',
    'MN': '몽골',
    'MO': '마카오(중국 특별행정구)',
    'MP': '북마리아나제도',
    'MQ': '마르티니크',
    'MR': '모리타니',
    'MS': '몬트세라트',
    'MT': '몰타',
    'MU': '모리셔스',
    'MV': '몰디브',
    'MW': '말라위',
    'MX': '멕시코',
    'MY': '말레이시아',
    'MZ': '모잠비크',
    'NA': '나미비아',
    'NC': '뉴칼레도니아',
    'NE': '니제르',
    'NF': '노퍽섬',
    'NG': '나이지리아',
    'NI': '니카라과',
    'NL': '네덜란드',
    'NO': '노르웨이',
    'NP': '네팔',
    'NR': '나우루',
    'NU': '니우에',
    'NZ': '뉴질랜드',
    'OM': '오만',
    'PA': '파나마',
    'PE': '페루',
    'PF': '프랑스령 폴리네시아',
    'PG': '파푸아뉴기니',
    'PH': '필리핀',
    'PK': '파키스탄',
    'PL': '폴란드',
    'PM': '생피에르 미클롱',
    'PN': '핏케언 제도',
    'PR': '푸에르토리코',
    'PS': '팔레스타인 지구',
    'PT': '포르투갈',
    'PW': '팔라우',
    'PY': '파라과이',
    'QA': '카타르',
    'RE': '레위니옹',
    'RO': '루마니아',
    'RS': '세르비아',
    'RU': '러시아',
    'RW': '르완다',
    'SA': '사우디아라비아',
    'SB': '솔로몬 제도',
    'SC': '세이셸',
    'SD': '수단',
    'SE': '스웨덴',
    'SG': '싱가포르',
    'SH': '세인트헬레나',
    'SI': '슬로베니아',
    'SJ': '스발바르제도-얀마웬섬',
    'SK': '슬로바키아',
    'SL': '시에라리온',
    'SM': '산마리노',
    'SN': '세네갈',
    'SO': '소말리아',
    'SR': '수리남',
    'SS': '남수단',
    'ST': '상투메 프린시페',
    'SV': '엘살바도르',
    'SX': '신트마르턴',
    'SY': '시리아',
    'SZ': '에스와티니',
    'TA': '트리스탄다쿠나',
    'TC': '터크스 케이커스 제도',
    'TD': '차드',
    'TG': '토고',
    'TH': '태국',
    'TJ': '타지키스탄',
    'TK': '토켈라우',
    'TL': '동티모르',
    'TM': '투르크메니스탄',
    'TN': '튀니지',
    'TO': '통가',
    'TR': '튀르키예',
    'TT': '트리니다드 토바고',
    'TV': '투발루',
    'TW': '대만',
    'TZ': '탄자니아',
    'UA': '우크라이나',
    'UG': '우간다',
    'US': '미국',
    'UY': '우루과이',
    'UZ': '우즈베키스탄',
    'VA': '바티칸 시국',
    'VC': '세인트빈센트그레나딘',
    'VE': '베네수엘라',
    'VG': '영국령 버진아일랜드',
    'VI': '미국령 버진아일랜드',
    'VN': '베트남',
    'VU': '바누아투',
    'WF': '왈리스-푸투나 제도',
    'WS': '사모아',
    'XK': '코소보',
    'YE': '예멘',
    'YT': '마요트',
    'ZA': '남아프리카',
    'ZM': '잠비아',
    'ZW': '짐바브웨'
  }
};
