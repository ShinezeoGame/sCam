import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../theme.dart';
import '../widgets/camera_widgets.dart';
import '../widgets/controls.dart';
import '../widgets/tiles.dart';
import 'page_scaffold.dart';

/// Écran : ajouter une caméra (appairage).
class PairPage extends StatefulWidget {
  const PairPage({super.key});

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final screen = app.screen;
    final t = context.text;
    if (screen == null) {
      return const AppPage(
        header: PageHeader(title: 'Ajouter une caméra'),
        children: [],
      );
    }
    final pairing = screen.pairing;
    final found = screen.pairable;
    return AppPage(
      header: const PageHeader(title: 'Ajouter une caméra'),
      children: [
        const NoticeArea(),
        if (pairing != null)
          Gap(
            child: PairingCodeTile(peerName: pairing.peerName, code: pairing.code, onAnswer: pairing.answer),
          ),
        Tile(
          child: const StepList([
            'Sur le téléphone caméra, ouvrez sCam et touchez « Appairer un écran ».',
            'Choisissez la caméra ci-dessous.',
            'Vérifiez que le même code s\'affiche sur les deux appareils, et confirmez des deux côtés.',
          ]),
        ),
        SectionTitle('Caméras prêtes', detail: found.isEmpty ? null : 'sur ce Wi-Fi'),
        if (found.isEmpty)
          const Gap(
            child: EmptyHint(
              icon: Icons.wifi_find_rounded,
              title: 'Recherche en cours…',
              text: 'Une caméra apparaît ici quand l\'appairage est ouvert sur elle, sur le même Wi-Fi.',
            ),
          )
        else
          for (final camera in found)
            Gap(
              child: Tile(
                child: Row(
                  children: [
                    const IconBadge(icon: Icons.videocam_rounded, tone: BadgeTone.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            camera.announcement.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.itemTitle,
                          ),
                          Text(camera.address.address, style: t.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Appairer',
                      compact: true,
                      kind: ButtonKind.primary,
                      busy: screen.pairingBusy,
                      onPressed: pairing == null ? () => screen.pair(camera.address, camera.announcement.port) : null,
                    ),
                  ],
                ),
              ),
            ),
        const SectionTitle('Par son adresse'),
        Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Si la caméra n\'apparaît pas (certaines box bloquent les annonces), saisissez l\'adresse '
                'affichée dans ses réglages.',
                style: t.secondary,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: '192.168.1.30'),
                onSubmitted: screen.pairByAddress,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Appairer',
                icon: Icons.link_rounded,
                busy: screen.pairingBusy,
                onPressed: pairing == null ? () => screen.pairByAddress(_address.text) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
