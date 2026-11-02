import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'local_store.dart';

/// Даёт ApiClient/UpdateService http.Client, который доверяет ИМЕННО тому
/// самоподписанному сертификату, который показывает конкретный сервер (см.
/// server/src/services/tls.js) — а не встроенному списку публичных
/// корневых сертификатов, где у самоподписанного сертификата, естественно,
/// никогда не будет записи.
///
/// Модель доверия — "довериться при первом подключении" (TOFU, тот же
/// принцип, что и у known_hosts в SSH): при самом первом обращении к
/// конкретному адресу сервера (ключ "host:port") приложение принимает тот
/// сертификат, который сервер предъявит в ответ, и запоминает его на
/// телефоне (LocalStore.pinnedCertificates). Все следующие обращения к
/// этому же адресу проверяются строго ТОЛЬКО против запомненного
/// сертификата — если сервер вдруг предъявит другой (например,
/// администратор перегенерировал сертификат после смены IP-адреса, либо
/// кто-то пытается подменить сервер в этой же сети), соединение будет
/// отклонено с понятной ошибкой (см. ApiException.certificateMismatch в
/// api_client.dart), а не тихо пройдёт как ни в чём не бывало.
///
/// Честная оговорка про этот подход: он не защищает от атаки "человек
/// посередине", которая произошла бы ровно в момент самого первого
/// подключения к новому адресу сервера (до этого момента запоминать ещё
/// нечего). Для этого проекта — локальный сервер в домашней/учебной
/// Wi-Fi-сети, адрес которого администратор сам вручную копирует из
/// панели администратора в приложение — этот риск принят сознательно,
/// это тот же уровень доверия, что и у большинства локальных
/// самоуправляемых устройств (роутеры, NAS, умный дом и т.п.).
///
/// Для обычных http:// адресов (сервер без HTTPS, либо адрес
/// Android-эмулятора по умолчанию без HTTPS) ничего из этого не
/// задействуется — используется обычный http.Client, поведение не меняется.
String hostPortKey(Uri uri) => '${uri.host}:${uri.port}';

http.Client buildClientFor(String baseUrl, LocalStore store) {
  final uri = Uri.parse(baseUrl);
  if (uri.scheme != 'https') return http.Client();

  final key = hostPortKey(uri);
  var pinnedPem = store.pinnedCertificates[key];
  // withTrustedRoots: false — сознательно НЕ доверяем встроенным публичным
  // корневым сертификатам вообще: этот клиент общается только с одним
  // конкретным самоподписанным сервером, доверие должно быть только к нему.
  final context = SecurityContext(withTrustedRoots: false);
  final rawClient = HttpClient(context: context);

  if (pinnedPem != null) {
    try {
      context.setTrustedCertificatesBytes(utf8.encode(pinnedPem));
    } catch (_) {
      // A corrupt saved pin fails closed until explicitly cleared in Settings.
    }
  }

  rawClient.badCertificateCallback =
      (X509Certificate cert, String host, int port) {
    if (host != uri.host || port != uri.port) return false;
    if (pinnedPem != null) {
      // Уже есть запомненный сертификат для этого адреса — доверяем ТОЛЬКО
      // ему. Раз проверка всё равно дошла до этого колбэка, значит
      // setTrustedCertificatesBytes выше не совпал с тем, что предъявил
      // сервер сейчас — соединение должно быть отклонено, а не тихо принято
      // здесь "на всякий случай".
      return false;
    }
    // Самое первое подключение к этому адресу — запоминаем ровно то, что
    // сервер предъявил сейчас (см. комментарий класса выше про модель TOFU).
    // Pin immediately in this reused client as well as asynchronously on disk.
    pinnedPem = cert.pem;
    context.setTrustedCertificatesBytes(utf8.encode(cert.pem));
    store.setPinnedCertificate(key, cert.pem).catchError((_) {});
    return true;
  };

  return IOClient(rawClient);
}
