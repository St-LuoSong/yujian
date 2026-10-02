import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/models/travel_models.dart';
import 'package:yujian_travel/screens/journey/day_card.dart';

/// 预算科目与时长文案的回归用例。
///
/// 两个缺陷都来自真机截图，不是凭空设计的边界：
/// 1. 预算拆解只剩一条"其他 ¥90 100%"——分类代码硬匹配中文 type，
///    而模型返回的是 attraction / transport；
/// 2. 体力风险写着"当天 3 个节点，约 59.1 小时"——时长解析把"3—4小时"
///    读成 34 小时，显示端又把分钟换算成一位小数的小时。
PlanStop _stop(String kind, String title, {int cost = 0, String? duration}) =>
    PlanStop('09:00', title, kind, '说明', cost, duration: duration);

void main() {
  group('StopCategory', () {
    test('classifies the English types the model actually returns', () {
      expect(StopCategory.of(_stop('attraction', '龙门石窟')),
          StopCategory.attraction);
      expect(StopCategory.of(_stop('transport', '郑州至洛阳铁路出行')),
          StopCategory.transport);
      expect(StopCategory.of(_stop('meal', '洛阳水席')), StopCategory.meal);
      expect(StopCategory.of(_stop('hotel', '云台山民宿')), StopCategory.hotel);
    });

    test('still understands the Chinese types the demo plan uses', () {
      expect(StopCategory.of(_stop('景点', '白马寺')), StopCategory.attraction);
      expect(StopCategory.of(_stop('餐饮', '鼓楼夜市')), StopCategory.meal);
      expect(StopCategory.of(_stop('住宿', '云台山周边')), StopCategory.hotel);
      expect(StopCategory.of(_stop('交通', '返程')), StopCategory.transport);
    });

    test('falls back to the title when the type tells us nothing', () {
      // type 不认识时才轮到标题说话：'活动' 是认识的类型，不能因为标题像餐馆就改判。
      expect(StopCategory.of(_stop('', '老洛阳面馆（午餐）')), StopCategory.meal);
      expect(StopCategory.of(_stop('活动', '老洛阳面馆（午餐）')),
          StopCategory.activity);
      expect(StopCategory.of(_stop('', '洛阳博物馆')), StopCategory.attraction);
      expect(StopCategory.of(_stop('unknown', '郑州东站')),
          StopCategory.transport);
      expect(StopCategory.of(_stop('', '自由活动')), StopCategory.activity);
      expect(StopCategory.of(_stop('', '办理入住')), StopCategory.hotel);
      expect(StopCategory.of(_stop('', '随便走走')), StopCategory.other);
    });

    test('labels are the Chinese words the page shows', () {
      expect(StopCategory.transport.label, '交通');
      expect(StopCategory.attraction.label, '景点');
      expect(StopCategory.other.label, '其他');
    });
  });

  group('day risks', () {
    test('a transport leg is not counted as a visit', () {
      final PlanDay day = PlanDay('DAY 01', '2026-10-02', <PlanStop>[
        _stop('transport', '郑州至洛阳铁路出行', duration: '约2小时'),
        _stop('attraction', '龙门石窟', cost: 90, duration: '约4小时'),
      ]);

      final RiskLine effort = deriveDayRisks(day)
          .firstWhere((RiskLine line) => line.title == '体力');

      expect(effort.reason, contains('当天 1 个节点'));
      expect(effort.reason, contains('停留约 4小时'));
      expect(effort.reason, isNot(contains('.')));
    });
  });

  group('duration text', () {
    test('reads hours and minutes together', () {
      expect(parseMinutes('约2小时30分钟'), 150);
      expect(parseMinutes('约4小时'), 240);
      expect(parseMinutes('45分钟'), 45);
      expect(parseMinutes('1小时30分'), 90);
    });

    test('reads a range at its upper bound instead of concatenating digits', () {
      // 旧实现把"3—4小时"的非数字字符全删掉，于是得到 34 小时。
      expect(parseMinutes('3—4小时'), 240);
      expect(parseMinutes('4-5小时'), 300);
    });

    test('never prints a fractional hour', () {
      expect(formatMinutes(150), '2小时30分钟');
      expect(formatMinutes(240), '4小时');
      expect(formatMinutes(45), '45分钟');
    });
  });
}
