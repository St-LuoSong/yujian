import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'form_controls.dart';

/// 河南省内城市（17 个地级市 + 济源示范区），按拼音首字母分组。
///
/// 分组不是装饰：弹层右侧有一列字母索引，用户按字母找城市，
/// 所以分组的顺序必须和索引一致。
const Map<String, List<String>> henanCitiesByInitial = <String, List<String>>{
  'A': <String>['安阳'],
  'H': <String>['鹤壁'],
  'J': <String>['济源', '焦作'],
  'K': <String>['开封'],
  'L': <String>['洛阳', '漯河'],
  'N': <String>['南阳'],
  'P': <String>['平顶山', '濮阳'],
  'S': <String>['三门峡', '商丘', '信阳'],
  'X': <String>['新乡', '许昌'],
  'Z': <String>['郑州', '周口', '驻马店'],
};

/// 省外热门出发地。河南本地的产品也得让外省游客找得到自己从哪里出发，
/// 否则「出发地」这一栏只对省内用户成立。
const List<String> nationwideHot = <String>[
  '北京', '上海', '广州', '深圳', '杭州', '南京',
  '苏州', '西安', '武汉', '成都', '重庆', '济南',
  '太原', '石家庄', '合肥', '长沙', '天津', '青岛',
];

/// 首屏先给这一屏。省外热门的城市排在它们的省份分组之后，不抢第一眼。
const List<String> _henanHot = <String>[
  '郑州', '洛阳', '开封', '焦作', '安阳', '新乡',
  '南阳', '许昌', '信阳', '商丘', '三门峡', '驻马店',
];

/// 城市选择弹层。参考 12306 的「选择出发」：上面是搜索，中间是热门，
/// 下面是分组全量，右侧一列字母索引。
///
/// 和之前的胶囊组相比，这一版的收益是「出发地」不再被写死成四个选项：
/// 搜不到的城市可以直接用输入的内容，从省外来的游客不会被挡住。
Future<String?> showCityPickerSheet(
  BuildContext context, {
  required String title,
  required String selected,
  List<String> recent = const <String>[],
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _CityPickerSheet(
        title: title,
        selected: selected,
        recent: recent,
      ),
    );

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({
    required this.title,
    required this.selected,
    required this.recent,
  });

  final String title;
  final String selected;
  final List<String> recent;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _groupKeys = <String, GlobalKey>{
    for (final String letter in henanCitiesByInitial.keys)
      letter: GlobalKey(debugLabel: 'city-group-$letter'),
  };

  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 全量城市池，用于搜索。顺序固定，搜出来的结果不会每次跳位置。
  List<String> get _pool {
    final List<String> cities = <String>[
      for (final List<String> group in henanCitiesByInitial.values) ...group,
      ...nationwideHot,
      ...widget.recent,
    ];
    final List<String> unique = <String>[];
    for (final String city in cities) {
      if (!unique.contains(city)) {
        unique.add(city);
      }
    }
    return unique;
  }

  List<String> get _matches {
    final String query = _query.trim();
    if (query.isEmpty) {
      return const <String>[];
    }
    return _pool.where((String city) => city.contains(query)).toList();
  }

  /// 搜到的结果里没有这个名字时，允许直接把输入内容当成城市。
  /// 只在输入不像一句废话时给出口：2—8 个字，且没有空格和标点。
  bool get _acceptsRawQuery {
    final String query = _query.trim();
    if (query.length < 2 || query.length > 8) {
      return false;
    }
    if (RegExp(r'[\s，。,.、,;；:：!！?？]').hasMatch(query)) {
      return false;
    }
    return !_matches.contains(query);
  }

  void _pick(String city) => Navigator.of(context).pop(city);

  void _jumpTo(String letter) {
    final BuildContext? target = _groupKeys[letter]?.currentContext;
    if (target == null) {
      return;
    }
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final double available =
        MediaQuery.sizeOf(context).height * 0.86 - keyboard;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: available < 260 ? 260 : available,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SheetHandle(),
                  const SizedBox(height: 14),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: AppTypography.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _searchField(),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _searchField() => TextField(
        controller: _search,
        autofocus: false,
        textInputAction: TextInputAction.search,
        onChanged: (String value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: '输入城市或地区',
          filled: true,
          fillColor: AppColors.ground,
          isDense: true,
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppColors.crackle,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  tooltip: '清空搜索',
                  icon: const Icon(Icons.close, size: 16),
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: _pillBorder(AppColors.hairline),
          enabledBorder: _pillBorder(AppColors.hairline),
          focusedBorder: _pillBorder(AppColors.celadon, width: 1.5),
        ),
      );

  Widget _body() {
    if (_query.trim().isNotEmpty) {
      return _searchResults();
    }
    return Stack(
      children: <Widget>[
        SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 30, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.recent.isNotEmpty) ...<Widget>[
                const _SectionTitle('最近使用'),
                _grid(widget.recent),
                const SizedBox(height: 18),
              ],
              const _SectionTitle('热门推荐'),
              _grid(_henanHot),
              const SizedBox(height: 18),
              const _SectionTitle('河南省内'),
              for (final MapEntry<String, List<String>> group
                  in henanCitiesByInitial.entries) ...<Widget>[
                Padding(
                  key: _groupKeys[group.key],
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    group.key,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w700,
                      color: AppColors.celadon,
                      letterSpacing: AppTypography.labelTracking,
                    ),
                  ),
                ),
                _grid(group.value),
                const SizedBox(height: 14),
              ],
              const _SectionTitle('省外热门'),
              _grid(nationwideHot),
            ],
          ),
        ),
        Positioned(
          right: 2,
          top: 4,
          bottom: 12,
          child: _LetterRail(
            letters: henanCitiesByInitial.keys.toList(),
            onTap: _jumpTo,
          ),
        ),
      ],
    );
  }

  Widget _searchResults() {
    final List<String> matches = _matches;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_acceptsRawQuery) ...<Widget>[
            _RawQueryTile(query: _query.trim(), onTap: _pick),
            const SizedBox(height: 16),
          ],
          if (matches.isEmpty && !_acceptsRawQuery)
            const Text(
              '没有找到这个城市。请换一个写法，或直接输入城市名。',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                color: AppColors.crackle,
                height: 1.6,
              ),
            )
          else ...<Widget>[
            const _SectionTitle('搜索结果'),
            _grid(matches),
          ],
        ],
      ),
    );
  }

  Widget _grid(List<String> cities) => GridView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 40,
        ),
        children: <Widget>[
          for (final String city in cities)
            _CityTile(
              label: city,
              selected: city == widget.selected,
              onTap: () => _pick(city),
            ),
        ],
      );
}

OutlineInputBorder _pillBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      borderSide: BorderSide(color: color, width: width),
    );

/// 一格城市。密度按 12306 的三列来：一屏能扫到十几个候选，
/// 而不是一行一个、滑半天。
class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusSmall);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.celadonDeep : AppColors.ground,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppTypography.secondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? AppColors.onInk : AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 搜索没命中时的出口：「使用『XX』」。
/// 这一条是给省外游客和县级地名留的，避免选择器把人挡住。
class _RawQueryTile extends StatelessWidget {
  const _RawQueryTile({required this.query, required this.onTap});

  final String query;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        BorderRadius.circular(AppSpacing.radiusControl);
    return Material(
      color: AppColors.surfaceTint,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(query),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.celadonPale),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.edit_location_alt_outlined,
                  size: 18,
                  color: AppColors.celadonDeep,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '使用「$query」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.celadonDeep,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: AppColors.celadonDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小标题：一道竖色条 + 标题。比整行加粗更省空间，也更容易扫。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.celadon,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: AppTypography.secondary,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      );
}

/// 右侧字母索引。点一个字母滚到对应的分组。
class _LetterRail extends StatelessWidget {
  const _LetterRail({required this.letters, required this.onTap});

  final List<String> letters;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          for (final String letter in letters)
            InkWell(
              onTap: () => onTap(letter),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Center(
                  child: Text(
                    letter,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.celadon,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
