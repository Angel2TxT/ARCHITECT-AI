"""Pruebas de reglas de negocio — proyectos casa hogar."""

from __future__ import annotations

import unittest
from types import SimpleNamespace

from fastapi import HTTPException

from services.home_project_service import (
    _require_unassigned_section_owner,
    _extract_mentions,
    _permissions_for_role,
    _REVIEW_STATUSES_REQUIRING_COMMENT,
    _validate_reopen_reason,
)
from db.models import HomeProjectSectionStatus


class PermissionsTests(unittest.TestCase):
    def test_owner_permissions(self):
        perms = _permissions_for_role("owner")
        self.assertTrue(perms["can_edit"])
        self.assertTrue(perms["can_review"])
        self.assertTrue(perms["can_manage_team"])
        self.assertTrue(perms["can_assign"])
        self.assertTrue(perms["can_advance_stage"])
        self.assertTrue(perms["can_reopen_section"])
        self.assertTrue(perms["is_project_owner"])

    def test_editor_permissions(self):
        perms = _permissions_for_role("editor")
        self.assertTrue(perms["can_edit"])
        self.assertTrue(perms["can_review"])
        self.assertFalse(perms["can_assign"])
        self.assertFalse(perms["can_manage_team"])
        self.assertFalse(perms["can_advance_stage"])
        self.assertFalse(perms["can_reopen_section"])
        self.assertFalse(perms["can_delete_section"])

    def test_admin_permissions(self):
        perms = _permissions_for_role("admin")
        self.assertTrue(perms["can_manage_team"])
        self.assertTrue(perms["can_assign"])
        self.assertTrue(perms["can_advance_stage"])
        self.assertTrue(perms["can_reopen_stage"])
        self.assertTrue(perms["is_global_admin"])

    def test_viewer_permissions(self):
        perms = _permissions_for_role("viewer")
        self.assertTrue(perms["can_view"])
        self.assertFalse(perms["can_edit"])
        self.assertFalse(perms["can_review"])
        self.assertFalse(perms["can_manage_team"])

    def test_none_role(self):
        perms = _permissions_for_role(None)
        self.assertFalse(any(perms.values()))


class ReopenReasonTests(unittest.TestCase):
    def test_valid_reason(self):
        text = _validate_reopen_reason("  Motivo válido de reapertura  ")
        self.assertEqual(text, "Motivo válido de reapertura")

    def test_short_reason_rejected(self):
        with self.assertRaises(HTTPException) as ctx:
            _validate_reopen_reason("corto")
        self.assertEqual(ctx.exception.status_code, 400)


class UnassignedSectionRuleTests(unittest.TestCase):
    def test_owner_can_work_unassigned_section(self):
        section = SimpleNamespace(assigned_to_user_id=None)
        _require_unassigned_section_owner(section, "owner")

    def test_admin_can_work_unassigned_section(self):
        section = SimpleNamespace(assigned_to_user_id=None)
        _require_unassigned_section_owner(section, "admin")

    def test_editor_cannot_work_unassigned_section(self):
        section = SimpleNamespace(assigned_to_user_id=None)
        with self.assertRaises(HTTPException) as ctx:
            _require_unassigned_section_owner(section, "editor")
        self.assertEqual(ctx.exception.status_code, 403)

    def test_editor_can_work_assigned_section(self):
        section = SimpleNamespace(assigned_to_user_id=123)
        _require_unassigned_section_owner(section, "editor")


class MentionTests(unittest.TestCase):
    def test_extract_single_mention(self):
        emails = _extract_mentions("Revisa @colaborador@empresa.com por favor")
        self.assertEqual(emails, ["colaborador@empresa.com"])

    def test_extract_multiple_unique(self):
        body = "@a@test.com y @b@test.com y otra vez @a@test.com"
        emails = _extract_mentions(body)
        self.assertEqual(sorted(emails), ["a@test.com", "b@test.com"])

    def test_no_mentions(self):
        self.assertEqual(_extract_mentions("Sin menciones aquí"), [])


class ReviewStatusTests(unittest.TestCase):
    def test_statuses_requiring_comment(self):
        self.assertIn(HomeProjectSectionStatus.needs_details, _REVIEW_STATUSES_REQUIRING_COMMENT)
        self.assertIn(HomeProjectSectionStatus.needs_correction, _REVIEW_STATUSES_REQUIRING_COMMENT)
        self.assertNotIn(HomeProjectSectionStatus.completed, _REVIEW_STATUSES_REQUIRING_COMMENT)


if __name__ == "__main__":
    unittest.main()
