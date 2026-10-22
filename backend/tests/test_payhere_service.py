"""
Unit tests for PayHereService — pure logic, no DB or HTTP.

Covers:
- _md5_upper helper
- _compute_hash / hash produced by build_initiate_params
- verify_callback_signature (valid, invalid, tampered, missing secret)
- validate_callback_fields (merchant_id, amount, currency mismatches)
- map_status_code (all known codes + unknown)
- _split_name edge cases
- _require_phone missing/present
- _assert_config_complete missing fields
- build_initiate_params field values (amount formatting, hash correctness)
"""
import hashlib
import uuid
from decimal import Decimal
from unittest.mock import patch, MagicMock

import pytest

from app.services.payhere import PayHereService, _md5_upper
from app.core.exceptions import BusinessLogicError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _md5(value: str) -> str:
    return hashlib.md5(value.encode("utf-8")).hexdigest().upper()


def _make_expected_hash(merchant_id: str, order_id: str, amount: str,
                         currency: str, secret: str) -> str:
    hashed_secret = _md5(secret)
    return _md5(merchant_id + order_id + amount + currency + hashed_secret)


def _make_callback_sig(merchant_id: str, order_id: str, amount: str,
                        currency: str, status_code: str, secret: str) -> str:
    hashed_secret = _md5(secret)
    return _md5(merchant_id + order_id + amount + currency + status_code + hashed_secret)


def _mock_settings(
    merchant_id="TEST_MERCHANT_123",
    secret="TEST_SECRET_abc",
    notify_url="https://example.ngrok.io/api/v1/payhere/callback",
    return_url="billingagent://payment/return",
    cancel_url="billingagent://payment/cancel",
    default_address="No. 1 Main Street",
    default_city="Colombo",
    default_country="Sri Lanka",
):
    """Return a mock settings object with PayHere fields configured."""
    m = MagicMock()
    m.PAYHERE_MERCHANT_ID = merchant_id
    m.PAYHERE_SECRET = secret
    m.PAYHERE_NOTIFY_URL = notify_url
    m.PAYHERE_RETURN_URL = return_url
    m.PAYHERE_CANCEL_URL = cancel_url
    m.PAYHERE_DEFAULT_ADDRESS = default_address
    m.PAYHERE_DEFAULT_CITY = default_city
    m.PAYHERE_DEFAULT_COUNTRY = default_country
    return m


def _mock_transaction(amount="100.00", currency="LKR"):
    tx = MagicMock()
    tx.id = uuid.UUID("12345678-1234-5678-1234-567812345678")
    tx.amount = Decimal(amount)
    tx.currency = currency
    return tx


def _mock_user(name="Kasun Perera", email="kasun@example.com", phone="+94771234567"):
    user = MagicMock()
    user.name = name
    user.email = email
    user.phone = phone
    return user


# ---------------------------------------------------------------------------
# _md5_upper
# ---------------------------------------------------------------------------

class TestMd5Upper:
    def test_produces_uppercase_hex(self):
        result = _md5_upper("hello")
        assert result == result.upper()
        assert len(result) == 32

    def test_known_value(self):
        # MD5("") uppercase
        assert _md5_upper("") == "D41D8CD98F00B204E9800998ECF8427E"

    def test_consistent(self):
        assert _md5_upper("abc") == _md5_upper("abc")

    def test_different_inputs_differ(self):
        assert _md5_upper("foo") != _md5_upper("bar")


# ---------------------------------------------------------------------------
# _split_name
# ---------------------------------------------------------------------------

class TestSplitName:
    def test_first_and_last(self):
        svc = PayHereService()
        assert svc._split_name("Kasun Perera") == ("Kasun", "Perera")

    def test_single_name(self):
        svc = PayHereService()
        first, last = svc._split_name("Kasun")
        assert first == "Kasun"
        assert last == ""

    def test_multi_word_last_name(self):
        svc = PayHereService()
        first, last = svc._split_name("Mohamed Ali Nafris")
        assert first == "Mohamed"
        assert last == "Ali Nafris"

    def test_leading_trailing_whitespace(self):
        svc = PayHereService()
        first, last = svc._split_name("  Kasun  Perera  ")
        assert first == "Kasun"
        assert last == "Perera"

    def test_empty_name(self):
        svc = PayHereService()
        first, last = svc._split_name("")
        assert first == ""
        assert last == ""


# ---------------------------------------------------------------------------
# _require_phone
# ---------------------------------------------------------------------------

class TestRequirePhone:
    def test_valid_phone_returned(self):
        svc = PayHereService()
        assert svc._require_phone("+94771234567") == "+94771234567"

    def test_none_raises(self):
        svc = PayHereService()
        with pytest.raises(BusinessLogicError, match="phone number"):
            svc._require_phone(None)

    def test_empty_string_raises(self):
        svc = PayHereService()
        with pytest.raises(BusinessLogicError, match="phone number"):
            svc._require_phone("")


# ---------------------------------------------------------------------------
# _assert_config_complete
# ---------------------------------------------------------------------------

class TestAssertConfigComplete:
    def test_all_present_does_not_raise(self):
        svc = PayHereService()
        mock = _mock_settings()
        with patch("app.services.payhere.settings", mock):
            svc._assert_config_complete()  # should not raise

    def test_missing_merchant_id_raises(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=None)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="PAYHERE_MERCHANT_ID"):
                svc._assert_config_complete()

    def test_missing_secret_raises(self):
        svc = PayHereService()
        mock = _mock_settings(secret=None)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="PAYHERE_SECRET"):
                svc._assert_config_complete()

    def test_missing_notify_url_raises(self):
        svc = PayHereService()
        mock = _mock_settings(notify_url=None)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="PAYHERE_NOTIFY_URL"):
                svc._assert_config_complete()

    def test_multiple_missing_listed(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=None, secret=None)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError) as exc_info:
                svc._assert_config_complete()
            msg = str(exc_info.value)
            assert "PAYHERE_MERCHANT_ID" in msg
            assert "PAYHERE_SECRET" in msg


# ---------------------------------------------------------------------------
# map_status_code
# ---------------------------------------------------------------------------

class TestMapStatusCode:
    def test_success(self):
        assert PayHereService().map_status_code("2") == "SUCCESS"

    def test_pending(self):
        assert PayHereService().map_status_code("0") == "PENDING"

    def test_cancelled(self):
        assert PayHereService().map_status_code("-1") == "CANCELLED"

    def test_failed(self):
        assert PayHereService().map_status_code("-2") == "FAILED"

    def test_chargedback_maps_to_failed(self):
        assert PayHereService().map_status_code("-3") == "FAILED"

    def test_unknown_returns_none(self):
        assert PayHereService().map_status_code("99") is None

    def test_empty_string_returns_none(self):
        assert PayHereService().map_status_code("") is None


# ---------------------------------------------------------------------------
# verify_callback_signature
# ---------------------------------------------------------------------------

class TestVerifyCallbackSignature:
    MERCHANT_ID = "TEST_MERCHANT_123"
    SECRET = "TEST_SECRET_abc"
    ORDER_ID = "12345678-1234-5678-1234-567812345678"
    AMOUNT = "100.00"
    CURRENCY = "LKR"
    STATUS_CODE = "2"

    def _valid_sig(self):
        return _make_callback_sig(
            self.MERCHANT_ID, self.ORDER_ID, self.AMOUNT,
            self.CURRENCY, self.STATUS_CODE, self.SECRET
        )

    def test_valid_signature_returns_true(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=self.MERCHANT_ID, secret=self.SECRET)
        with patch("app.services.payhere.settings", mock):
            result = svc.verify_callback_signature(
                merchant_id=self.MERCHANT_ID,
                order_id=self.ORDER_ID,
                payhere_amount=self.AMOUNT,
                payhere_currency=self.CURRENCY,
                status_code=self.STATUS_CODE,
                md5sig=self._valid_sig(),
            )
        assert result is True

    def test_tampered_amount_returns_false(self):
        svc = PayHereService()
        mock = _mock_settings(secret=self.SECRET)
        with patch("app.services.payhere.settings", mock):
            result = svc.verify_callback_signature(
                merchant_id=self.MERCHANT_ID,
                order_id=self.ORDER_ID,
                payhere_amount="999.00",  # tampered
                payhere_currency=self.CURRENCY,
                status_code=self.STATUS_CODE,
                md5sig=self._valid_sig(),
            )
        assert result is False

    def test_tampered_status_code_returns_false(self):
        svc = PayHereService()
        mock = _mock_settings(secret=self.SECRET)
        with patch("app.services.payhere.settings", mock):
            result = svc.verify_callback_signature(
                merchant_id=self.MERCHANT_ID,
                order_id=self.ORDER_ID,
                payhere_amount=self.AMOUNT,
                payhere_currency=self.CURRENCY,
                status_code="-2",   # tampered from "2"
                md5sig=self._valid_sig(),
            )
        assert result is False

    def test_tampered_md5sig_returns_false(self):
        svc = PayHereService()
        mock = _mock_settings(secret=self.SECRET)
        with patch("app.services.payhere.settings", mock):
            result = svc.verify_callback_signature(
                merchant_id=self.MERCHANT_ID,
                order_id=self.ORDER_ID,
                payhere_amount=self.AMOUNT,
                payhere_currency=self.CURRENCY,
                status_code=self.STATUS_CODE,
                md5sig="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            )
        assert result is False

    def test_missing_secret_returns_false(self):
        svc = PayHereService()
        mock = _mock_settings(secret=None)
        with patch("app.services.payhere.settings", mock):
            result = svc.verify_callback_signature(
                merchant_id=self.MERCHANT_ID,
                order_id=self.ORDER_ID,
                payhere_amount=self.AMOUNT,
                payhere_currency=self.CURRENCY,
                status_code=self.STATUS_CODE,
                md5sig=self._valid_sig(),
            )
        assert result is False

    def test_sig_is_case_insensitive_on_received_side(self):
        """md5sig from PayHere should match regardless of case on their end."""
        svc = PayHereService()
        mock = _mock_settings(secret=self.SECRET)
        lowercase_sig = self._valid_sig().lower()
        with patch("app.services.payhere.settings", mock):
            result = svc.verify_callback_signature(
                merchant_id=self.MERCHANT_ID,
                order_id=self.ORDER_ID,
                payhere_amount=self.AMOUNT,
                payhere_currency=self.CURRENCY,
                status_code=self.STATUS_CODE,
                md5sig=lowercase_sig,
            )
        assert result is True


# ---------------------------------------------------------------------------
# validate_callback_fields
# ---------------------------------------------------------------------------

class TestValidateCallbackFields:
    MERCHANT_ID = "TEST_MERCHANT_123"
    AMOUNT = "100.00"
    CURRENCY = "LKR"

    def _make_tx(self):
        return _mock_transaction(amount=self.AMOUNT, currency=self.CURRENCY)

    def test_all_matching_does_not_raise(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=self.MERCHANT_ID)
        with patch("app.services.payhere.settings", mock):
            svc.validate_callback_fields(
                merchant_id=self.MERCHANT_ID,
                payhere_amount=self.AMOUNT,
                payhere_currency=self.CURRENCY,
                transaction=self._make_tx(),
            )

    def test_wrong_merchant_id_raises(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=self.MERCHANT_ID)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="merchant_id"):
                svc.validate_callback_fields(
                    merchant_id="ATTACKER_MERCHANT",
                    payhere_amount=self.AMOUNT,
                    payhere_currency=self.CURRENCY,
                    transaction=self._make_tx(),
                )

    def test_wrong_amount_raises(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=self.MERCHANT_ID)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="amount"):
                svc.validate_callback_fields(
                    merchant_id=self.MERCHANT_ID,
                    payhere_amount="999.00",
                    payhere_currency=self.CURRENCY,
                    transaction=self._make_tx(),
                )

    def test_wrong_currency_raises(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=self.MERCHANT_ID)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="currency"):
                svc.validate_callback_fields(
                    merchant_id=self.MERCHANT_ID,
                    payhere_amount=self.AMOUNT,
                    payhere_currency="USD",
                    transaction=self._make_tx(),
                )

    def test_invalid_decimal_amount_raises(self):
        svc = PayHereService()
        mock = _mock_settings(merchant_id=self.MERCHANT_ID)
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="valid decimal"):
                svc.validate_callback_fields(
                    merchant_id=self.MERCHANT_ID,
                    payhere_amount="not-a-number",
                    payhere_currency=self.CURRENCY,
                    transaction=self._make_tx(),
                )


# ---------------------------------------------------------------------------
# build_initiate_params — field values and hash correctness
# ---------------------------------------------------------------------------

class TestBuildInitiateParams:
    MERCHANT_ID = "SANDBOX_MERCHANT"
    SECRET = "SANDBOX_SECRET"
    NOTIFY_URL = "https://abc.ngrok.io/api/v1/payhere/callback"
    RETURN_URL = "billingagent://payment/return"
    CANCEL_URL = "billingagent://payment/cancel"

    def _mock_s(self):
        return _mock_settings(
            merchant_id=self.MERCHANT_ID,
            secret=self.SECRET,
            notify_url=self.NOTIFY_URL,
            return_url=self.RETURN_URL,
            cancel_url=self.CANCEL_URL,
        )

    def test_amount_formatted_to_two_decimal_places(self):
        svc = PayHereService()
        tx = _mock_transaction(amount="100", currency="LKR")
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        assert resp.amount == "100.00"

    def test_hash_matches_expected_formula(self):
        svc = PayHereService()
        tx = _mock_transaction(amount="250.00", currency="LKR")
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)

        expected = _make_expected_hash(
            self.MERCHANT_ID, str(tx.id), "250.00", "LKR", self.SECRET
        )
        assert resp.hash == expected

    def test_merchant_id_in_response(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        assert resp.merchant_id == self.MERCHANT_ID

    def test_order_id_is_transaction_id_string(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        assert resp.order_id == str(tx.id)

    def test_name_split_correctly(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user(name="Kasun Perera")
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        assert resp.first_name == "Kasun"
        assert resp.last_name == "Perera"

    def test_urls_populated_from_config(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        assert resp.notify_url == self.NOTIFY_URL
        assert resp.return_url == self.RETURN_URL
        assert resp.cancel_url == self.CANCEL_URL

    def test_missing_phone_raises(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user(phone=None)
        with patch("app.services.payhere.settings", self._mock_s()):
            with pytest.raises(BusinessLogicError, match="phone number"):
                svc.build_initiate_params(tx, user)

    def test_missing_config_raises(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user()
        mock = _mock_settings(notify_url=None)  # missing NOTIFY_URL
        with patch("app.services.payhere.settings", mock):
            with pytest.raises(BusinessLogicError, match="PAYHERE_NOTIFY_URL"):
                svc.build_initiate_params(tx, user)

    def test_address_defaults_from_config(self):
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        assert resp.address == "No. 1 Main Street"
        assert resp.city == "Colombo"
        assert resp.country == "Sri Lanka"

    def test_secret_not_in_response(self):
        """The PAYHERE_SECRET must never appear anywhere in the returned response."""
        svc = PayHereService()
        tx = _mock_transaction()
        user = _mock_user()
        with patch("app.services.payhere.settings", self._mock_s()):
            resp = svc.build_initiate_params(tx, user)
        response_str = resp.model_dump_json()
        assert self.SECRET not in response_str
