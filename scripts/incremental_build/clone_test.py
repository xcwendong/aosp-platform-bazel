# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import unittest

from clone import GoList


class CloneTest(unittest.TestCase):
  def test_go_list(self):
    golist = GoList('''
        import blah
        package blue
        type X
        var (
          empty = []string{
          }
          more = []string{
            "a",
            "b", // comment
          }
        )
    '''.splitlines(keepends=True))
    L = len(golist.lines)

    with self.assertRaises(RuntimeError):
      golist.locate('non-existing')

    self.assertEqual(-1, golist.begin)
    self.assertEqual(-1, golist.end)

    golist.locate('empty')
    self.assertNotEqual(-1, golist.begin)
    self.assertNotEqual(-1, golist.end)
    self.assertEqual(golist.begin, golist.end)
    self.assertFalse(golist.has_module("a"))
    golist.insert_clones("a", 3)
    self.assertEqual(3, golist.end - golist.begin)
    self.assertTrue(golist.has_module("a-1"))
    self.assertTrue(golist.has_module("a-2"))
    self.assertTrue(golist.has_module("a-3"))
    self.assertEqual(L + 3, len(golist.lines))

    golist.locate('more')
    self.assertEqual(2, golist.end - golist.begin)
    self.assertTrue(golist.has_module("a"))
    self.assertTrue(golist.has_module("b"))
