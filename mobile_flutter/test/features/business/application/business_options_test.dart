import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/business/application/business_providers.dart';

void main() {
  test('parses dashboard industry labels while preserving API codes', () {
    final options = BusinessOnboardingOptions.fromJson({
      'Industries': [
        {
          'Key': 'TECHNOLOGY',
          'Value': 'Technology',
          'SubIndustries': [
            {
              'Key': 'IT_AND_COMPUTER_SERVICES',
              'Value': 'IT and Computer Services',
            },
          ],
        },
      ],
    });

    final industry = options.industries.single;
    expect(industry.key, 'TECHNOLOGY');
    expect(industry.label, 'Technology');
    expect(industry.subIndustries.single.key, 'IT_AND_COMPUTER_SERVICES');
    expect(industry.subIndustries.single.label, 'IT and Computer Services');
  });

  test('accepts camel-case options wrapped in a data envelope', () {
    final options = BusinessOnboardingOptions.fromJson({
      'data': {
        'industries': [
          {
            'key': 'RETAIL',
            'value': 'Retail',
            'subIndustries': [
              {'key': 'E_COMMERCE', 'value': 'E Commerce'},
            ],
          },
        ],
      },
    });

    expect(options.industries.single.key, 'RETAIL');
    expect(options.industries.single.subIndustries.single.key, 'E_COMMERCE');
  });
}
