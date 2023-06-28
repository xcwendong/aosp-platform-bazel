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
import io
import textwrap
import unittest
from typing import TextIO

from pretty import summarize


class PrettyTest(unittest.TestCase):

  def test_summarize(self):
    def metrics() -> TextIO:
      return io.StringIO(textwrap.dedent(
          'build_result,build_type,description,targets,a,ab,ac\n'
          'SUCCESS,B1,WARMUP,nothing,1,10,1:00\n'
          'SUCCESS,B1,do it,something,10,200\n'
          'SUCCESS,B1,rebuild-1,something,4,,1:04\n'
          'SUCCESS,B1,rebuild-2,something,6,55,1:07\n'
          'TEST_FAILURE,B2,do it,something,601\n'
          'TEST_FAILURE,B2,do it,nothing,3600\n'
          'TEST_FAILURE,B2,undo it,something,240\n'
          'FAILED,B3,,,70000,70000,7:00:00'))

    with self.subTest('a$'):
      result = summarize(metrics(), 'a$')
      self.assertEqual(len(result), 1)
      self.assertEqual(result['a'],
                       'cuj,targets,B1,B2\n'
                       'WARMUP,nothing,1,\n'
                       'do it,something,10,601\n'
                       'do it,nothing,,3600\n'
                       'rebuild,something,5[N=2],\n'
                       'undo it,something,,240'
                       )

    with self.subTest('a.$'):
      result = summarize(metrics(), 'a.$')
      self.assertEqual(len(result), 2)
      self.assertEqual(result['ab'],
                       'cuj,targets,B1,B2\n'
                       'WARMUP,nothing,10,\n'
                       'do it,something,200,\n'
                       'do it,nothing,,\n'
                       'rebuild,something,55,\n'
                       'undo it,something,,'
                       )
      self.assertEqual(result['ac'],
                       'cuj,targets,B1,B2\n'
                       'WARMUP,nothing,01:00,\n'
                       'do it,something,,\n'
                       'do it,nothing,,\n'
                       'rebuild,something,01:06[N=2],\n'
                       'undo it,something,,'
                       )

      with self.subTest('multiple patterns'):
        result = summarize(metrics(), 'ab', 'ac')
        self.assertEqual(len(result), 2)


if __name__ == '__main__':
  unittest.main()
