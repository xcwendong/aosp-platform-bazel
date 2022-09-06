#!/usr/bin/env python3

# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Tests for dependency_analysis.py."""

import dependency_analysis
import unittest
import xml.etree.ElementTree as ElementTree


def _make_json_dep(name, tag=None, variations=None):
  return {
      'Name': name,
      'Tag': tag,
      'Variations': variations,
  }


def _make_json_variation(mutator, variation):
  return {
      'Mutator': mutator,
      'Variation': variation,
  }


def _make_json_module(name, typ, deps, variations=None):
  return {
      'Name': name,
      'Type': typ,
      'Deps': deps,
      'Variations': variations,
  }


def _make_xml_module(full_name,
                     name,
                     kind,
                     variant='',
                     dep_names=[],
                     soong_module_type=None,
                     srcs=None):
  rule = ElementTree.Element('rule', attrib={'class': kind, 'name': full_name})
  ElementTree.SubElement(
      rule, 'string', attrib={
          'name': 'soong_module_name',
          'value': name
      })
  ElementTree.SubElement(
      rule, 'string', attrib={
          'name': 'soong_module_variant',
          'value': variant
      })
  if soong_module_type:
    ElementTree.SubElement(
        rule,
        'string',
        attrib={
            'name': 'soong_module_type',
            'value': soong_module_type
        })
  for dep in dep_names:
    ElementTree.SubElement(rule, 'rule-input', attrib={'name': dep})

  if not srcs:
    return rule

  src_element = ElementTree.SubElement(rule, 'list', attrib={'name': 'srcs'})
  for src in srcs:
    ElementTree.SubElement(src_element, 'string', attrib={'value': src})

  return rule


class DependencyAnalysisTest(unittest.TestCase):

  def test_visit_json_module_graph_post_order_visits_all_in_post_order(self):
    graph = [
        _make_json_module('q', 'module', [
            _make_json_dep('a'),
            _make_json_dep('b'),
        ]),
        _make_json_module('a', 'module', [
            _make_json_dep('b'),
            _make_json_dep('c'),
        ]),
        _make_json_module('b', 'module', [
            _make_json_dep('d'),
        ]),
        _make_json_module('c', 'module', [
            _make_json_dep('e'),
        ]),
        _make_json_module('d', 'module', []),
        _make_json_module('e', 'module', []),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['d', 'b', 'e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_json_module_graph_post_order_skips_ignored_by_name_and_transitive(
      self):
    graph = [
        _make_json_module('a', 'module', [
            _make_json_dep('b'),
            _make_json_dep('c'),
        ]),
        _make_json_module('b', 'module', [
            _make_json_dep('d'),
        ]),
        _make_json_module('c', 'module', [
            _make_json_dep('e'),
        ]),
        _make_json_module('d', 'module', []),
        _make_json_module('e', 'module', []),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set('b'), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_json_module_graph_post_order_skips_defaults_and_transitive(
      self):
    graph = [
        _make_json_module('a', 'module', [
            _make_json_dep('b'),
            _make_json_dep('c'),
        ]),
        _make_json_module('b', 'module_defaults', [
            _make_json_dep('d'),
        ]),
        _make_json_module('c', 'module', [
            _make_json_dep('e'),
        ]),
        _make_json_module('d', 'module', []),
        _make_json_module('e', 'module', []),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_json_module_graph_post_order_skips_windows_and_transitive(
      self):
    windows_variation = _make_json_variation('os', 'windows')
    graph = [
        _make_json_module('a', 'module', [
            _make_json_dep('b', variations=[windows_variation]),
            _make_json_dep('c'),
        ]),
        _make_json_module(
            'b',
            'module',
            [
                _make_json_dep('d'),
            ],
            [windows_variation],
        ),
        _make_json_module('c', 'module', [
            _make_json_dep('e'),
        ]),
        _make_json_module('d', 'module', []),
        _make_json_module('e', 'module', []),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_json_module_graph_post_order_skips_prebuilt_tag_deps(self):
    graph = [
        _make_json_module('a', 'module', [
            _make_json_dep(
                'b', 'android.prebuiltDependencyTag {BaseDependencyTag:{}}'),
            _make_json_dep('c'),
        ]),
        _make_json_module('b', 'module', [
            _make_json_dep('d'),
        ]),
        _make_json_module('c', 'module', [
            _make_json_dep('e'),
        ]),
        _make_json_module('d', 'module', []),
        _make_json_module('e', 'module', []),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_json_module_graph_post_order_no_infinite_loop_for_self_dep(
      self):
    graph = [
        _make_json_module('a', 'module', [_make_json_dep('a')]),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_json_module_graph_post_order_visits_all_variants(self):
    graph = [
        _make_json_module(
            'a',
            'module',
            [
                _make_json_dep('b'),
            ],
            [_make_json_variation('m', '1')],
        ),
        _make_json_module(
            'a',
            'module',
            [
                _make_json_dep('c'),
            ],
            [_make_json_variation('m', '2')],
        ),
        _make_json_module('b', 'module', [
            _make_json_dep('d'),
        ]),
        _make_json_module('c', 'module', [
            _make_json_dep('e'),
        ]),
        _make_json_module('d', 'module', []),
        _make_json_module('e', 'module', []),
    ]

    def only_a(json):
      return json['Name'] == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module['Name'])

    dependency_analysis.visit_json_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['d', 'b', 'a', 'e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_visits_all(self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a', 'a', 'module', dep_names=['//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module('//pkg:b', 'b', 'module', dep_names=['//pkg:d']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['d', 'b', 'e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_skips_ignore_by_name(
      self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a', 'a', 'module', dep_names=['//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module('//pkg:b', 'b', 'module', dep_names=['//pkg:d']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set('b'), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_skips_default(self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a', 'a', 'module', dep_names=['//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module(
            '//pkg:b', 'b', 'module_defaults', dep_names=['//pkg:d']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_skips_cc_prebuilt(self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a', 'a', 'module', dep_names=['//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module(
            '//pkg:b', 'b', 'cc_prebuilt_library', dep_names=['//pkg:d']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_skips_filegroup_duplicate_name(
      self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a', 'a', 'module', dep_names=['//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module(
            '//pkg:b', 'b', 'filegroup', dep_names=['//pkg:d'], srcs=['b']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_skips_windows(self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a', 'a', 'module', dep_names=['//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module(
            '//pkg:b',
            'b',
            'module',
            dep_names=['//pkg:d'],
            variant='windows-x86'))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_self_dep_no_infinite_loop(
      self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a',
            'a',
            'module',
            dep_names=['//pkg:b--variant1', '//pkg:c']))
    graph.append(
        _make_xml_module(
            '//pkg:b--variant1',
            'b',
            'module',
            variant='variant1',
            dep_names=['//pkg:b--variant2']))
    graph.append(
        _make_xml_module(
            '//pkg:b--variant2',
            'b',
            'module',
            variant='variant2',
            dep_names=['//pkg:d']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['d', 'b', 'b', 'e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)

  def test_visit_queryview_xml_module_graph_post_order_skips_prebuilt_with_same_name(
      self):
    graph = ElementTree.Element('query', attrib={'version': '2'})
    graph.append(
        _make_xml_module(
            '//pkg:a',
            'a',
            'module',
            dep_names=['//other_pkg:prebuilt_a', '//pkg:b', '//pkg:c']))
    graph.append(
        _make_xml_module('//other_pkg:prebuilt_a', 'prebuilt_a',
                         'prebuilt_module'))
    graph.append(
        _make_xml_module('//pkg:b', 'b', 'module', dep_names=['//pkg:d']))
    graph.append(
        _make_xml_module('//pkg:c', 'c', 'module', dep_names=['//pkg:e']))
    graph.append(_make_xml_module('//pkg:d', 'd', 'module'))
    graph.append(_make_xml_module('//pkg:e', 'e', 'module'))

    def only_a(module):
      return module.name == 'a'

    visited_modules = []

    def visit(module, _):
      visited_modules.append(module.name)

    dependency_analysis.visit_queryview_xml_module_graph_post_order(
        graph, set(), only_a, visit)

    expected_visited = ['d', 'b', 'e', 'c', 'a']
    self.assertListEqual(visited_modules, expected_visited)


if __name__ == '__main__':
  unittest.main()
