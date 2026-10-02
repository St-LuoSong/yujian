import '../models/travel_models.dart';

const imageLongmen =
    'https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=1200&q=80';
const imageShaolin =
    'https://images.unsplash.com/photo-1528360983277-13d401cdc186?auto=format&fit=crop&w=1200&q=80';
const imageYuntai =
    'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1200&q=80';
const imageKaifeng =
    'https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=1200&q=80';

const destinations = <Destination>[
  Destination(
      id: 'longmen',
      name: '龙门石窟',
      city: '洛阳',
      theme: '人文古迹',
      image: imageLongmen,
      summary: '一壁看尽千年风物，石刻造像沿伊河两岸铺展。',
      ticket: 90,
      duration: '3—4小时',
      audience: '历史文化爱好者',
      weatherTip: '雨天仍可游览，建议穿舒适防滑鞋。'),
  Destination(
      id: 'shaolin',
      name: '嵩山少林',
      city: '登封',
      theme: '人文古迹',
      image: imageShaolin,
      summary: '少林、塔林与三皇寨，共同构成一条可慢慢阅读的文明长廊。',
      ticket: 80,
      duration: '4—5小时',
      audience: '文化与户外',
      weatherTip: '山路较多，雨天注意防滑。'),
  Destination(
      id: 'yuntai',
      name: '云台山',
      city: '焦作',
      theme: '山水秘境',
      image: imageYuntai,
      summary: '红石峡碧水丹崖，泉瀑峡银链垂空，把大自然的层次留给脚步。',
      ticket: 120,
      duration: '1—2天',
      audience: '自然风光爱好者',
      weatherTip: '适合晴天和低降雨时段。'),
  Destination(
      id: 'qingming',
      name: '清明上河园',
      city: '开封',
      theme: '宋韵生活',
      image: imageKaifeng,
      summary: '一朝步入画卷，一日梦回千年，宋韵市井在此重新展开。',
      ticket: 120,
      duration: '半天—1天',
      audience: '城市漫游',
      weatherTip: '适合下午入园并关注演出时间。'),
];

const corridors = <TravelCorridor>[
  TravelCorridor('郑州—开封', '古都烟火里的宋韵一日', '1—2天', '¥300起', imageKaifeng,
      ['古都文化', '夜游美食', '城市漫游']),
  TravelCorridor('郑州—洛阳', '沿着伊河读懂千年中原', '2—3天', '¥680起', imageLongmen,
      ['龙门石窟', '博物馆', '古都深度游']),
  TravelCorridor('焦作—云台山', '把山水留给周末的脚步', '1—2天', '¥520起', imageYuntai,
      ['红石峡', '自然风光', '轻户外']),
];

TravelPlan demoPlan({String destination = '洛阳', int people = 2}) {
  if (destination.contains('开封')) {
    return _plan(title: '开封宋韵一日游', corridor: '郑州—开封', people: people, days: [
      PlanDay('DAY 01', '宋韵一日', [
        PlanStop('09:30', '开封府', '景点', '郑州东 → 开封约35分钟', 65),
        PlanStop('13:30', '清明上河园', '景点', '建议下午入园并预留夜游', 120),
        PlanStop('19:00', '鼓楼夜市', '餐饮', '本地特色小吃探索', 70)
      ])
    ]);
  }
  if (destination.contains('云台')) {
    return _plan(title: '云台山周末轻旅行', corridor: '焦作—云台山', people: people, days: [
      PlanDay('DAY 01', '红石峡与潭瀑峡', [
        PlanStop('08:30', '红石峡', '景点', '建议穿舒适防滑鞋', 120),
        PlanStop('14:00', '潭瀑峡', '景点', '根据天气情况调整', 0),
        PlanStop('18:00', '云台山周边', '住宿', '建议提前确认房态', 180)
      ]),
      PlanDay('DAY 02', '山顶风物', [
        PlanStop('09:00', '茱萸峰', '景点', '户外活动受天气影响', 60),
        PlanStop('15:00', '返程', '交通', '预留山路和换乘时间', 100)
      ])
    ]);
  }
  return _plan(title: '洛阳历史文化两日游', corridor: '郑州—洛阳', people: people, days: [
    PlanDay('DAY 01', '古都与石窟', [
      PlanStop('09:00', '龙门石窟', '景点', '高铁站 → 景区约45分钟', 90),
      PlanStop('14:00', '洛阳博物馆', '景点', '从龙门石窟前往约30分钟', 0),
      PlanStop('18:30', '洛阳水席', '餐饮', '建议预留90分钟', 80)
    ]),
    PlanDay('DAY 02', '古寺与城市', [
      PlanStop('09:00', '白马寺', '景点', '建议游览2小时', 35),
      PlanStop('13:30', '隋唐洛阳城', '景点', '城市漫游与夜景', 60),
      PlanStop('17:30', '返程', '交通', '预留换乘缓冲时间', 120)
    ])
  ]);
}

/// Builds a bundled demo plan whose headline cost is the sum of its item costs.
///
/// Keeping the total derived means the itinerary, the metric row and the budget
/// tab always agree, which is how the server computes generated plans too.
TravelPlan _plan({
  required String title,
  required String corridor,
  required int people,
  required List<PlanDay> days,
}) {
  final stops = days.expand((day) => day.stops).toList();
  final total = stops.fold<int>(0, (sum, stop) => sum + stop.cost);
  return TravelPlan(
      title: title,
      corridor: corridor,
      people: people,
      totalCost: total,
      days: days,
      intensity: _intensityFor(stops.length),
      warnings: const ['门票、开放时间和交通信息请以官方渠道为准。', '当前为本地演示方案，调整、撤销与依据需要连接服务器。']);
}

/// Same thresholds the server uses in `TripPlanFactory.inferIntensity`.
String _intensityFor(int stopCount) {
  if (stopCount <= 3) {
    return '轻松';
  }
  return stopCount <= 6 ? '适中' : '紧凑';
}
