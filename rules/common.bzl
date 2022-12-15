"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

def get_dep_targets(ctx, *, predicate = lambda _: True, skipped_attributes = []):
    """get_dep_targets returns all targets listed in the current rule's attributes

    Args:
        ctx (rule context): a rule context
        predicate (function(Target) -> bool): a function used to filter out
            unwanted targets
        skipped_attributes (list[str]): names of attributes to skip returning
            targets for
    Returns:
        targets (list[Target]): list of targets under attributes not in skipped
            attributes, and for which predicate returns True
    """
    targets = []
    for a in dir(ctx.rule.attr):
        if a.startswith("_") or a in skipped_attributes:
            # Ignore private attributes
            continue
        value = getattr(ctx.rule.attr, a)
        vlist = value if type(value) == type([]) else [value]
        for item in vlist:
            if type(item) == "Target" and predicate(item):
                targets.append(item)
    return targets
