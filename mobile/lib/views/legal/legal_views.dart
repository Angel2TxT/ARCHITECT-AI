import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';

class TermsOfServiceView extends StatelessWidget {
  const TermsOfServiceView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScaffold(
      title: 'Términos y condiciones',
      kicker: 'LEGAL',
      lastUpdated: '7 de agosto de 2026',
      intro:
          'Estos términos regulan el uso de ARCHITECT («el servicio»), una plataforma de revisión asistida de planos arquitectónicos, chat de construcción y gestión de proyectos de vivienda. Al registrarte, iniciar sesión o usar el servicio, aceptas estos términos y la política de privacidad.',
      sections: [
        _LegalSectionData(
          title: '1. Naturaleza del servicio',
          body:
              'ARCHITECT es un proyecto académico / de demostración. Ofrece apoyo técnico asistido por software e inteligencia artificial. No sustituye proyecto ejecutivo firmado, dictamen oficial, responsiva de obra, supervisión profesional ni trámites ante autoridades municipales o estatales.\n\nLos resultados (detecciones, avisos, medidas sugeridas, respuestas del chat) son orientativos y pueden contener errores. Debes validarlos con un profesional facultado antes de tomar decisiones de diseño, construcción o cumplimiento normativo.',
        ),
        _LegalSectionData(
          title: '2. Elegibilidad y cuenta',
          bullets: [
            'Debes tener al menos 18 años o la mayoría de edad en tu jurisdicción.',
            'Eres responsable de la veracidad de los datos de registro y de custodiar tu contraseña o acceso OAuth.',
            'No compartas tu cuenta. El uso indebido puede llevar a suspensión o eliminación.',
            'Puedes solicitar el cierre de tu cuenta al administrador del despliegue.',
          ],
        ),
        _LegalSectionData(
          title: '3. Planes, límites y pagos',
          bullets: [
            'El acceso a funciones puede estar limitado por plan (análisis de planos al mes, preguntas al chat, almacenamiento, proyectos casa hogar, etc.).',
            'En modo demo / académico, los «pagos» y comprobantes son simulados: no constituyen factura fiscal ni cobro real, salvo que el despliegue active una pasarela real y se indique claramente en el checkout.',
            'Los límites se reinician según el periodo del plan (típicamente mensual). Agotar el cupo puede bloquear nuevas acciones hasta el siguiente periodo o un cambio de plan.',
          ],
        ),
        _LegalSectionData(
          title: '4. Contenido que subes',
          bullets: [
            'Declaras tener derecho a subir planos, documentos y mensajes (titularidad, licencia o autorización).',
            'No subas material ilegal, malicioso, o datos personales sensibles innecesarios (domicilios exactos, datos de terceros sin base legal, etc.).',
            'Nos otorgas una licencia limitada para almacenar y procesar ese contenido solo para operar el servicio (análisis, chat, proyectos, respaldos técnicos).',
            'Conservas tus derechos sobre el contenido original; ARCHITECT no reclama propiedad de tus planos.',
          ],
        ),
        _LegalSectionData(
          title: '5. Uso aceptable',
          body: 'Te comprometes a no:',
          bullets: [
            'Intentar vulnerar la seguridad, acceder a cuentas ajenas o sobrecargar el sistema de forma abusiva.',
            'Usar el servicio para engañar a terceros presentando resultados de IA como dictamen oficial.',
            'Extraer masivamente datos, modelos o contenido de otros usuarios sin autorización.',
            'Reutilizar la marca ARCHITECT de forma que sugiera aval profesional o gubernamental inexistente.',
          ],
        ),
        _LegalSectionData(
          title: '6. Inteligencia artificial y terceros',
          body:
              'Partes del servicio pueden depender de proveedores externos (modelos de visión/LLM, correo, OAuth, hosting o túneles). Su disponibilidad y políticas propias pueden afectar el funcionamiento. Al usar funciones de IA, aceptas que prompts y fragmentos de planos puedan enviarse a esos proveedores conforme a la configuración del despliegue y a la política de privacidad.',
        ),
        _LegalSectionData(
          title: '7. Propiedad intelectual de la plataforma',
          body:
              'El software, diseño, marca, documentación y materiales de ARCHITECT pertenecen a sus autores o licenciantes. No puedes copiar, revender o redistribuir el producto sin permiso, salvo lo permitido por la ley o por acuerdo expreso del proyecto académico.',
        ),
        _LegalSectionData(
          title: '8. Disponibilidad y cambios',
          body:
              'El servicio se ofrece «tal cual» y «según disponibilidad». Puede haber interrupciones, errores o cambios de funciones sin aviso previo, especialmente en entornos de demostración o túneles temporales. Podemos modificar estos términos; la fecha de actualización indica la versión vigente.',
        ),
        _LegalSectionData(
          title: '9. Limitación de responsabilidad',
          body:
              'En la máxima medida permitida por la ley, ARCHITECT y sus responsables no serán responsables por daños indirectos, lucro cesante, decisiones de obra basadas en resultados del sistema, ni por incumplimiento normativo derivado del uso del servicio. La responsabilidad total, si existiera, se limita a lo estrictamente exigible por ley para un proyecto académico de demostración.',
        ),
        _LegalSectionData(
          title: '10. Indemnidad',
          body:
              'Aceptas indagar y, en la medida aplicable, mantener indemne al proyecto frente a reclamaciones de terceros derivadas de tu uso indebido del servicio o del contenido que subas.',
        ),
        _LegalSectionData(
          title: '11. Ley aplicable',
          body:
              'Salvo norma imperativa en contrario, estos términos se interpretan conforme a las leyes aplicables en México / el estado de Chiapas, sin perjuicio de derechos del consumidor que no puedan renunciarse.',
        ),
        _LegalSectionData(
          title: '12. Contacto',
          body:
              'Para dudas sobre estos términos: canal de ayuda / soporte dentro de ARCHITECT o el administrador del despliegue.',
        ),
      ],
    );
  }
}

class PrivacyPolicyView extends StatelessWidget {
  const PrivacyPolicyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScaffold(
      title: 'Política de privacidad',
      kicker: 'LEGAL',
      lastUpdated: '7 de agosto de 2026',
      intro:
          'Esta política describe cómo ARCHITECT («nosotros», «el servicio») trata la información personal y los archivos que subes al usar la plataforma de revisión asistida de planos, el chat de construcción y los proyectos de vivienda (casa hogar).\n\nARCHITECT es un proyecto académico / de demostración. No sustituye dictámenes oficiales, proyecto ejecutivo firmado ni responsiva de obra. Al crear una cuenta o usar el servicio, aceptas esta política.',
      sections: [
        _LegalSectionData(
          title: '1. Responsable',
          body:
              'El tratamiento de datos se realiza en el contexto del proyecto ARCHITECT. Para solicitudes relacionadas con privacidad puedes escribir al correo configurado como remitente del servicio (contacto del administrador del despliegue).',
        ),
        _LegalSectionData(
          title: '2. Datos que recopilamos',
          bullets: [
            'Cuenta: correo electrónico, nombre, contraseña (almacenada de forma cifrada/hash) o identificadores de inicio de sesión con Google (OAuth), y foto de perfil si la autorizas.',
            'Uso del plan: suscripción, límites mensuales de análisis y preguntas, historial de comprobantes de compra simulada (modo demo) y, si aplica, referencias de pago.',
            'Contenido que envías: planos (imágenes/PDF), mensajes del chat, correcciones, documentos de proyectos casa hogar y metadatos asociados (fechas, tamaños, títulos).',
            'Prueba sin cuenta (guest): un identificador en cookie para limitar análisis y preguntas de prueba.',
            'Técnicos: registros de errores del servidor, dirección IP aproximada vista por infraestructura y preferencias locales (tema claro/oscuro en la aplicación).',
          ],
        ),
        _LegalSectionData(
          title: '3. Para qué usamos los datos',
          bullets: [
            'Crear y autenticar tu cuenta.',
            'Ejecutar análisis de planos, responder preguntas de construcción y gestionar proyectos.',
            'Aplicar límites del plan (análisis y preguntas al mes).',
            'Enviar correos transaccionales (recuperación de contraseña, invitaciones, comprobantes).',
            'Mejorar el servicio, depurar fallos y prevenir abuso.',
            'Cumplir obligaciones académicas o legales aplicables al proyecto.',
          ],
        ),
        _LegalSectionData(
          title: '4. Tratamiento con IA y terceros',
          bullets: [
            'Modelos de visión / LLM: el contenido de planos y prompts puede enviarse a proveedores de IA configurados en el despliegue (por ejemplo Gemini u otros) para generar respuestas y hallazgos. No uses datos sensibles que no debas compartir con esos proveedores.',
            'Correo: los envíos pueden realizarse mediante Brevo (SMTP/API) u otro proveedor configurado en el entorno.',
            'Google OAuth: si inicias sesión con Google, se aplican además las políticas de Google respecto a la información que autorizas compartir.',
            'Hosting / túnel: el tráfico puede pasar por infraestructura de terceros según cómo se publique el servicio.',
          ],
        ),
        _LegalSectionData(
          title: '5. Conservación',
          body:
              'Conservamos la cuenta, chats, análisis y archivos mientras la cuenta exista o sea necesaria para el funcionamiento del proyecto. Puedes solicitar la eliminación de tu cuenta al administrador; tras eliminarla, los datos asociados se borran o se anonimizan en la medida técnica posible, salvo respaldos o registros que deban retenerse por un periodo breve por seguridad.',
        ),
        _LegalSectionData(
          title: '6. Cookies y almacenamiento local',
          bullets: [
            'Cookie / identificador de prueba guest (límites sin cuenta).',
            'Token de sesión y datos de usuario/suscripción en almacenamiento seguro del dispositivo.',
            'Preferencia de tema (claro/oscuro).',
          ],
        ),
        _LegalSectionData(
          title: '7. Seguridad',
          body:
              'Aplicamos medidas razonables (hash de contraseñas, control de acceso por roles, HTTPS cuando el despliegue lo permite). Ningún sistema es 100% seguro: evita subir planos con datos personales innecesarios (nombres de propietarios, domicilios exactos, etc.) si no es imprescindible.',
        ),
        _LegalSectionData(
          title: '8. Tus derechos',
          body:
              'Según la legislación aplicable (p. ej. LFPDPPP en México), puedes solicitar acceso, rectificación, cancelación u oposición respecto a tus datos personales, así como la eliminación de cuenta, contactando al responsable del despliegue. Responderemos en un plazo razonable.',
        ),
        _LegalSectionData(
          title: '9. Menores',
          body:
              'El servicio no está dirigido a menores de 18 años. Si un menor registró una cuenta sin autorización, contacta al administrador para eliminarla.',
        ),
        _LegalSectionData(
          title: '10. Compras y modo demo',
          body:
              'En modo de facturación demo, los «pagos» y comprobantes son simulados con fines académicos y no constituyen factura fiscal ni cobro real, salvo que el despliegue active una pasarela de pago real y se te informe claramente en el checkout.',
        ),
        _LegalSectionData(
          title: '11. Cambios',
          body:
              'Podemos actualizar esta política. La fecha de «última actualización» indica la versión vigente. El uso continuado del servicio tras un cambio relevante implica que conoces la nueva versión.',
        ),
        _LegalSectionData(
          title: '12. Contacto',
          body:
              'Para dudas sobre privacidad o ejercicio de derechos: usa el canal de ayuda / soporte dentro de ARCHITECT o el correo del administrador del proyecto.',
        ),
      ],
    );
  }
}

class _LegalSectionData {
  const _LegalSectionData({
    required this.title,
    this.body,
    this.bullets,
  });

  final String title;
  final String? body;
  final List<String>? bullets;
}

class _LegalDocumentScaffold extends StatelessWidget {
  const _LegalDocumentScaffold({
    required this.title,
    required this.kicker,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
  });

  final String title;
  final String kicker;
  final String lastUpdated;
  final String intro;
  final List<_LegalSectionData> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final pageBg = isDark ? colorScheme.surface : AppColors.dashboardSurface;
    final cardBg = theme.cardColor;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? colorScheme.outlineVariant : const Color(0xFFE2E4E9),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        kicker,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Actualizado: $lastUpdated',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  intro,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...sections.map(
            (section) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? colorScheme.outlineVariant.withValues(alpha: 0.5)
                      : const Color(0xFFEBECEF),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (section.body != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      section.body!,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (section.bullets != null && section.bullets!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...section.bullets!.map(
                      (bullet) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                bullet,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
