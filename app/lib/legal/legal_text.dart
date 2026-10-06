/// The Gizlilik & Kullanım Şartları text, and the support contact.
///
/// **DRAFT.** Written from what the app actually stores (see
/// docs/accounts-and-ranked.md and the migrations), NOT reviewed by a
/// lawyer. Have it reviewed before the release (docs/release.md).
///
/// The privacy policy is also in docs/privacy-policy.md, which is the copy
/// to host at a public URL for the Play Console. Keep the two in step:
/// test/legal_text_test.dart fails when a section title here is missing
/// from that file.
library;

/// One titled card on the Gizlilik screen (Figma 92:270, `Bölüm/...`).
class LegalSection {
  const LegalSection(this.title, this.body);
  final String title;
  final String body;
}

class SupportConfig {
  SupportConfig._();

  /// The address from the Destek frame (92:310).
  ///
  /// TODO(release): make sure this mailbox exists (or replace it) before the
  /// release — it is on the store listing, in the privacy policy and on the
  /// Destek screen.
  static const email = 'destek@321football.app';
}

class LegalText {
  LegalText._();

  static const lastUpdated = '6 Ekim 2026';

  static const draftNotice =
      'TASLAK — Bu metin henüz hukuki olarak gözden geçirilmedi. Yayından '
      'önce güncellenecektir.';

  /// The controller named in the policy.
  ///
  /// TODO(release): the developer's (or company's) legal name and address.
  static const controller = '[GELİŞTİRİCİ ADI / ŞİRKET UNVANI VE ADRESİ]';

  static const privacy = <LegalSection>[
    LegalSection(
      'Kim olduğumuz',
      '321 Football ("oyun"), $controller tarafından geliştirilen bağımsız '
          'bir futbol bilgi oyunudur. Bu politika, oyunun hangi verileri '
          'neden işlediğini anlatır. 6698 sayılı Kişisel Verilerin Korunması '
          'Kanunu (KVKK) ve AB Genel Veri Koruma Tüzüğü (GDPR) kapsamında '
          'veri sorumlusu geliştiricidir.',
    ),
    LegalSection(
      'Hangi verileri topluyoruz',
      '• Anonim hesap kimliği: oyunu ilk açtığında senin için rastgele bir '
          'kullanıcı kimliği oluşturulur. Ad, e-posta veya telefon '
          'istemiyoruz.\n'
          '• Kullanıcı adın ve otomatik oluşturulan 4 karakterlik etiketin '
          '(ör. Yaman#7K2M).\n'
          '• Oyun istatistiklerin: oynanan maç, galibiyet, güncel ve en iyi '
          'seri, en hızlı doğru cevap süresi, kupa puanın ve altın bakiyen.\n'
          '• Arkadaşlık bağlantıların ve bekleyen arkadaşlık isteklerin.\n'
          '• Maç odaları: oda kodu, iki oyuncunun kimliği ve kullanıcı adı, '
          'seçilen kulüpler, doğru cevaplar ve cevap süreleri, skor ve '
          'bağlantının kopup kopmadığını anlamak için son görülme zamanı.\n'
          '• Sıralı maç kuyruğu: eşleşme beklerken kimliğin ve kupa puanın.\n'
          '• Google hesabını bağlarsan (özellik açıldığında): Google\'ın '
          'sağladığı hesap kimliği ve e-posta adresin.\n'
          '• Reklam: yalnızca "2X Altın" reklamını yüklediğimizde Google '
          'AdMob; cihazının reklam kimliğini, IP adresini ve cihaz '
          'bilgilerini işler (aşağıdaki "Reklamlar" bölümü).\n'
          'Konum, rehber, fotoğraf, mikrofon veya ödeme bilgisi toplamıyoruz.',
    ),
    LegalSection(
      'Cihazında kalanlar',
      'Futbolcu ve kulüp veritabanı, ses ve titreşim ayarların, kullanıcı '
          'adının bir kopyası ve oturum anahtarın yalnızca cihazında tutulur. '
          'Alıştırma modunda yazdıkların cihazdan çıkmaz; Arkadaş Maçı ve '
          'Sıralı Maç\'ta yalnızca doğru cevabın ve süresi odaya yazılır.',
    ),
    LegalSection(
      'Verilerini nasıl kullanıyoruz',
      'Hesabını ve maçlarını çalıştırmak, sıralı maçta seni benzer kupa '
          'puanındaki rakiplerle eşleştirmek, liderlik tablolarını '
          'hesaplamak, arkadaş listeni tutmak, maç sonuçlarını, kupa ve '
          'altınları kaydetmek ve izlediğin ödüllü reklamın karşılığını '
          'vermek için. Verilerini satmıyor, kiralamıyor ve seni reklam için '
          'profillemiyoruz. Hukuki sebep: oyun hizmetini sunmak (sözleşmenin '
          'ifası) ve reklamlarda, gerektiğinde, açık rızan.',
    ),
    LegalSection(
      'Diğer oyuncuların gördükleri',
      'Kullanıcı adın, etiketin, kupa puanın ve maç istatistiklerin diğer '
          'oyunculara görünür (liderlik tabloları, arkadaş listeleri, maç '
          'ekranları). Maç odalarını yalnızca o maçtaki iki oyuncu görebilir.',
    ),
    LegalSection(
      'Hizmet sağlayıcılarımız',
      '• Supabase Inc.: veritabanı, kimlik doğrulama ve gerçek zamanlı maç '
          'sunucusu. Verilerin Supabase adına Amazon Web Services\'in AB '
          '(İrlanda, eu-west-1) bölgesinde saklanır. Supabase, bizim adımıza '
          've talimatımızla çalışan veri işleyendir.\n'
          '• Google LLC (AdMob): ödüllü reklamlar. Google, reklam verilerini '
          'kendi gizlilik politikasına göre işler: '
          'policies.google.com/privacy\n'
          '• Google LLC (Google ile Giriş): yalnızca hesabını Google\'a '
          'bağlarsan.\n'
          '• Google Play: oyunun dağıtımı.\n'
          'Bu nedenle verilerin Türkiye dışına (AB ve ABD) aktarılır. '
          'Oyunu kullanarak ve hesap oluşturarak bu aktarıma onay vermiş '
          'olursun (KVKK m. 9).',
    ),
    LegalSection(
      'Reklamlar',
      'Oyunda tek bir reklam vardır: sıralı maç galibiyetinden sonra '
          'isteğe bağlı olarak izleyebileceğin "2X Altın" ödüllü reklamı. '
          'Banner veya geçiş reklamı yoktur. Avrupa Ekonomik Alanı ve '
          'Birleşik Krallık\'ta reklamlar için önce onayın istenir. Reklam '
          'kimliğini Android ayarlarından (Gizlilik → Reklamlar) sıfırlayabilir '
          'veya silebilirsin.',
    ),
    LegalSection(
      'Ne kadar süre saklıyoruz',
      'Hesap verilerin, hesabın silinene kadar. Maç odaları en geç 1 gün '
          'içinde otomatik olarak silinir. Kuyruk kaydı eşleştiğinde veya '
          'aramayı iptal ettiğinde silinir. Silinen veriler, sağlayıcının '
          'yedeklerinden en geç 30 gün içinde kalkar.',
    ),
    LegalSection(
      'Hesabını ve verilerini silme',
      'Ayarlar → Destek & İletişim → "Hesabımı sil" ile hesabını istediğin '
          'zaman silebilirsin. Onayladığında profilin, kullanıcı adın ve '
          'etiketin, istatistiklerin, kupa ve altınların, arkadaşlıkların, '
          'kuyruk kaydın ve anonim kimliğin hemen ve kalıcı olarak silinir; '
          'geri alınamaz. Uygulamayı kaldırmak hesabını silmez. Uygulamaya '
          'erişemiyorsan kullanıcı adını ve etiketini ${SupportConfig.email} '
          'adresine yaz, 30 gün içinde sileriz.',
    ),
    LegalSection(
      'Çocukların gizliliği',
      'Oyun 13 yaş altına yönelik değildir. 13 yaşından küçük bir '
          'kullanıcıya ait veri tespit edersek hesabı ve verileri sileriz.',
    ),
    LegalSection(
      'Hakların',
      'KVKK m. 11 ve GDPR kapsamında verilerine erişme, düzeltilmesini '
          '(kullanıcı adını Profil\'den kendin değiştirebilirsin), '
          'silinmesini, işlenmesine itiraz etmeyi ve verilerinin bir '
          'kopyasını istemeyi talep edebilirsin. Taleplerini '
          '${SupportConfig.email} adresine gönder. Kişisel Verileri Koruma '
          'Kurulu\'na veya bulunduğun ülkedeki veri koruma otoritesine '
          'şikâyette bulunma hakkın saklıdır.',
    ),
    LegalSection(
      'Güvenlik',
      'Uygulama ile sunucu arasındaki tüm trafik şifrelidir (HTTPS). '
          'Sunucuda her oyuncu yalnızca kendi verisini ve kendi maç odasını '
          'değiştirebilir.',
    ),
    LegalSection(
      'Değişiklikler',
      'Bu politikayı güncellediğimizde yukarıdaki tarihi değiştirir, önemli '
          'değişiklikleri oyun içinde duyururuz.',
    ),
  ];

  static const terms = <LegalSection>[
    LegalSection(
      'Kabul',
      'Oyunu indirip kullanarak bu şartları kabul etmiş olursun. Kabul '
          'etmiyorsan oyunu kullanma ve hesabını sil.',
    ),
    LegalSection(
      'Hesabın ve kullanıcı adın',
      'Hesabın anonimdir ve cihazına bağlıdır; uygulamayı silersen (hesabını '
          'Google\'a bağlamadıysan) ilerlemene geri dönemezsin. Kullanıcı '
          'adın hakaret, nefret söylemi, cinsel içerik veya başka birini '
          'taklit eden ifadeler içeremez. Bu kurallara uymayan adları '
          'değiştirebilir veya hesabı askıya alabiliriz.',
    ),
    LegalSection(
      'Adil oyun',
      'Otomatik cevap araçları, başkası adına oynamak ve kasıtlı maç kaybı '
          'yasaktır. Bize bildirilen ihlallerde kupa puanları sıfırlanabilir '
          'veya hesap askıya alınabilir.',
    ),
    LegalSection(
      'Altın ve kupalar',
      'Altın ve kupalar yalnızca oyun içinde kullanılan sanal öğelerdir; '
          'gerçek para değerleri yoktur, satılamaz, devredilemez ve paraya '
          'çevrilemez. Oyunda satın alma yoktur. Oyun ekonomisini (ödül '
          'miktarları, Cevap ücreti) değiştirebiliriz.',
    ),
    LegalSection(
      'Futbolcu ve kulüp verisi',
      'Oyundaki transfer arşivi Wikidata\'dan derlenmiştir ve CC0 '
          'lisansıyla kullanılmaktadır; eksik veya hatalı kayıtlar olabilir. '
          'Kulüp adları sahiplerinin markalarıdır ve yalnızca tanımlama '
          'amacıyla kullanılır. Oyunda gerçek kulüp armaları kullanılmaz. '
          '321 Football hiçbir kulüp, lig veya federasyonla bağlantılı '
          'değildir.',
    ),
    LegalSection(
      'Hizmetin sunulması',
      'Oyun "olduğu gibi" sunulur. Çevrimiçi modların kesintisiz '
          'çalışacağını garanti etmeyiz; bakım, kesinti veya bağlantı '
          'sorunlarında yarım kalan maçlar ve kaybedilen ödüller için '
          'sorumluluk kabul etmeyiz. Oyunu değiştirebilir veya sona '
          'erdirebiliriz.',
    ),
    LegalSection(
      'Sona erme',
      'Hesabını istediğin zaman Destek & İletişim ekranından silebilirsin. '
          'Bu şartları ihlal eden hesapları askıya alabilir veya silebiliriz.',
    ),
    LegalSection(
      'Uygulanacak hukuk',
      'Bu şartlar Türkiye Cumhuriyeti kanunlarına tabidir. Tüketici '
          'olarak bulunduğun ülkenin zorunlu koruma hükümleri saklıdır.',
    ),
    LegalSection(
      'İletişim',
      'Sorularını ${SupportConfig.email} adresine iletebilirsin. Yasal '
          'bildirimler için de aynı adresi kullan.',
    ),
  ];
}
