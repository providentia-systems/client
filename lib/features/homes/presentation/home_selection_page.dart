import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';

final class HomeSelectionPage extends StatefulWidget {
  const HomeSelectionPage({
    required this.controller,
    this.sessionActiveHomeId,
    this.loadOnStart = true,
    this.activeHomeBuilder,
    this.accountPageBuilder,
    this.onSignOut,
    super.key,
  });

  final HomesController controller;
  final String? sessionActiveHomeId;
  final bool loadOnStart;
  final Widget Function(BuildContext context, HomeSummary home)?
  activeHomeBuilder;
  final WidgetBuilder? accountPageBuilder;
  final Future<void> Function()? onSignOut;

  @override
  State<HomeSelectionPage> createState() => _HomeSelectionPageState();
}

final class _HomeSelectionPageState extends State<HomeSelectionPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _locale = TextEditingController(text: 'en-NA');
  final TextEditingController _currency = TextEditingController(text: 'NAD');
  final TextEditingController _timezone = TextEditingController(
    text: 'Africa/Windhoek',
  );
  bool _showCreate = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnStart) {
      unawaited(
        widget.controller.load(sessionActiveHomeId: widget.sessionActiveHomeId),
      );
    }
  }

  @override
  void didUpdateWidget(covariant HomeSelectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.loadOnStart) {
      return;
    }
    if (oldWidget.controller != widget.controller || !oldWidget.loadOnStart) {
      unawaited(
        widget.controller.load(sessionActiveHomeId: widget.sessionActiveHomeId),
      );
      return;
    }
    if (oldWidget.sessionActiveHomeId == widget.sessionActiveHomeId) {
      return;
    }
    unawaited(
      widget.controller.reconcileSessionActiveHome(widget.sessionActiveHomeId),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _locale.dispose();
    _currency.dispose();
    _timezone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        if (snapshot.hasActiveHome && widget.activeHomeBuilder != null) {
          return widget.activeHomeBuilder!(context, snapshot.activeHome!);
        }
        return Scaffold(
          key: const Key('home-selection-page'),
          appBar: widget.accountPageBuilder == null && widget.onSignOut == null
              ? null
              : AppBar(
                  title: const Text('Providentia'),
                  actions: <Widget>[
                    if (widget.accountPageBuilder != null)
                      IconButton(
                        key: const Key('home-chooser-account-access'),
                        tooltip: 'Account & access',
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: widget.accountPageBuilder!,
                          ),
                        ),
                        icon: const Icon(Icons.manage_accounts_outlined),
                      ),
                    if (widget.onSignOut != null)
                      IconButton(
                        key: const Key('home-chooser-sign-out'),
                        tooltip: 'Sign out',
                        onPressed: () => unawaited(widget.onSignOut!()),
                        icon: const Icon(Icons.logout_rounded),
                      ),
                  ],
                ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: CustomScrollView(
                  slivers: <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                      sliver: SliverToBoxAdapter(child: _header(snapshot)),
                    ),
                    if (snapshot.pendingInvitations.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        sliver: SliverList.separated(
                          itemCount: snapshot.pendingInvitations.length,
                          itemBuilder: (context, index) => _invitationCard(
                            snapshot.pendingInvitations[index],
                          ),
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                        ),
                      ),
                    if (snapshot.homes.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.separated(
                          itemCount: snapshot.homes.length,
                          itemBuilder: (context, index) => _homeCard(
                            snapshot.homes[index],
                            snapshot.activeHome?.id,
                          ),
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.all(24),
                      sliver: SliverToBoxAdapter(
                        child: _createSection(snapshot),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(HomeSessionSnapshot snapshot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            'Choose your home',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Each home has its own members, stock, purchases, settings, and AI providers.',
        ),
        if (widget.controller.isBusy) ...<Widget>[
          const SizedBox(height: 20),
          const LinearProgressIndicator(
            key: Key('homes-loading'),
            semanticsLabel: 'Loading authorized homes',
          ),
        ],
        if (snapshot.safeMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            container: true,
            child: Text(
              snapshot.safeMessage!,
              key: const Key('homes-safe-message'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _homeCard(HomeSummary home, String? activeHomeId) {
    final selected = home.id == activeHomeId;
    return Card(
      child: Semantics(
        selected: selected,
        button: true,
        label: '${home.name}, ${home.role.name}',
        child: ListTile(
          key: Key('home-option-${home.id}'),
          leading: CircleAvatar(
            child: Icon(selected ? Icons.home_rounded : Icons.home_outlined),
          ),
          title: Text(home.name),
          subtitle: Text(
            '${home.role.name} · ${home.locale} · ${home.currency} · ${home.timezone}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: !widget.controller.isBusy,
          onTap: () => unawaited(widget.controller.selectHome(home.id)),
        ),
      ),
    );
  }

  Widget _invitationCard(RecipientHomeInvitation invitation) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        key: Key('pending-home-invitation-${invitation.id}'),
        leading: const Icon(Icons.mark_email_unread_outlined),
        title: Text('Invitation to ${invitation.homeName}'),
        subtitle: Text(
          '${invitation.role.name} access · from ${invitation.inviterDisplayName ?? 'a home member'}',
        ),
        trailing: FilledButton(
          onPressed: widget.controller.isBusy
              ? null
              : () => unawaited(
                  widget.controller.acceptPendingInvitation(invitation),
                ),
          child: const Text('Accept'),
        ),
      ),
    );
  }

  Widget _createSection(HomeSessionSnapshot snapshot) {
    final noHomes = snapshot.homes.isEmpty;
    // Invited first-time people land here with zero homes: their invitations
    // render first and creating a home stays an explicit secondary choice.
    // Only with neither homes nor invitations does the create form lead.
    final invitationsLead = noHomes && snapshot.pendingInvitations.isNotEmpty;
    if (!_showCreate && (!noHomes || invitationsLead)) {
      return OutlinedButton.icon(
        key: const Key('show-create-home'),
        onPressed: widget.controller.isBusy
            ? null
            : () => setState(() => _showCreate = true),
        icon: const Icon(Icons.add_home_outlined),
        label: Text(noHomes ? 'Create a home instead' : 'Create another home'),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  noHomes ? 'Create your first home' : 'Create a home',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('create-home-name'),
                controller: _name,
                enabled: !widget.controller.isBusy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Home name',
                  hintText: 'Our home',
                  prefixIcon: Icon(Icons.home_work_outlined),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: 180,
                    child: TextFormField(
                      key: const Key('create-home-locale'),
                      controller: _locale,
                      enabled: !widget.controller.isBusy,
                      decoration: const InputDecoration(labelText: 'Locale'),
                      validator: _required,
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      key: const Key('create-home-currency'),
                      controller: _currency,
                      enabled: !widget.controller.isBusy,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      validator: (value) =>
                          RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Use 3 letters.',
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextFormField(
                      key: const Key('create-home-timezone'),
                      controller: _timezone,
                      enabled: !widget.controller.isBusy,
                      decoration: const InputDecoration(labelText: 'Time zone'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('create-home-submit'),
                onPressed: widget.controller.isBusy ? null : _createHome,
                icon: const Icon(Icons.add_home_rounded),
                label: const Text('Create and open home'),
              ),
              if (!noHomes || snapshot.pendingInvitations.isNotEmpty)
                TextButton(
                  key: const Key('cancel-create-home'),
                  onPressed: widget.controller.isBusy
                      ? null
                      : () => setState(() => _showCreate = false),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _createHome() {
    if (_form.currentState?.validate() ?? false) {
      unawaited(
        widget.controller.createHome(
          name: _name.text,
          locale: _locale.text,
          currency: _currency.text,
          timezone: _timezone.text,
        ),
      );
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}
