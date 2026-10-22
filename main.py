"""QANOT backend integration scaffold.

This service intentionally returns HTTP 503 for operator, SMS and payment actions
until authorized provider credentials and adapters are configured. It never invents
balances, tariff prices, SMS delivery, or payment success.
"""
from typing import Literal
import os
import re
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI(title="QANOT API", version="0.1.0")

allowed_origins = [x.strip() for x in os.getenv("QANOT_ALLOWED_ORIGINS", "*").split(",") if x.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "Idempotency-Key"],
)

OPERATORS = ["Beeline", "Ucell", "UzMobile", "Mobiuz", "Humans"]
PROVIDERS = ["payme", "click"]

class BalanceRequest(BaseModel):
    phone: str = Field(min_length=9, max_length=20)
    operator: str

class SmsStartRequest(BaseModel):
    phone: str = Field(min_length=9, max_length=20)

class SmsVerifyRequest(BaseModel):
    phone: str = Field(min_length=9, max_length=20)
    code: str = Field(min_length=4, max_length=8)

class PaymentRequest(BaseModel):
    phone: str = Field(min_length=9, max_length=20)
    amount_uzs: int = Field(gt=0, le=10_000_000)
    provider: Literal["payme", "click"]


def validate_phone(phone: str) -> None:
    digits = re.sub(r"\D", "", phone)
    if len(digits) < 9 or len(digits) > 15:
        raise HTTPException(status_code=422, detail="Telefon raqami formati noto‘g‘ri.")


def not_configured(feature: str) -> None:
    raise HTTPException(
        status_code=503,
        detail=f"{feature} hali rasmiy provayder bilan sozlanmagan. Haqiqiy ma'lumot qaytarilmadi.",
    )

@app.get("/")
def root():
    return {"app": "QANOT", "version": "0.1.0", "status": "setup_required"}

@app.get("/health")
def health():
    return {"status": "ok", "service": "QANOT API"}

@app.get("/operators")
def operators():
    return {"items": OPERATORS}

@app.get("/tariffs")
def tariffs():
    # Empty until approved, current tariff data source is configured.
    return {"items": [], "verified": False, "message": "Tarif ma'lumotlari manbasi hali ulanmagan."}

@app.post("/balance")
def balance(data: BalanceRequest):
    validate_phone(data.phone)
    if data.operator not in OPERATORS:
        raise HTTPException(status_code=422, detail="Operator tanlovi noto‘g‘ri.")
    not_configured("Balans tekshirish")

@app.post("/auth/sms/start")
def sms_start(data: SmsStartRequest):
    validate_phone(data.phone)
    not_configured("SMS tasdiqlash")

@app.post("/auth/sms/verify")
def sms_verify(data: SmsVerifyRequest):
    validate_phone(data.phone)
    not_configured("SMS kodini tekshirish")

@app.post("/payments/create")
def create_payment(data: PaymentRequest):
    validate_phone(data.phone)
    not_configured("To‘lov yaratish")

@app.get("/transactions")
def transactions():
    # This endpoint must later require an authenticated user token.
    return {"items": [], "configured": False, "message": "Avtorizatsiya va tranzaksiya bazasi sozlanmagan."}
