"""Writes what OpenAI's Python SDK makes of the pydantic counterparts of the `strict()` parity test types.

`StrictSchemaParityTests` compares `strict()` with these files byte for byte. Each model here is the pydantic model
a Swift type stands for: a `@Schema` struct is a model that forbids extra keys, a `String` enum is a `Literal`, a
union enum is a `RootModel` of a `Union`, and a tagged union's variants carry their tag as a `Literal` field last.

    python3 -m venv .venv && .venv/bin/pip install openai==3.58.0 pydantic==2.14.4
    .venv/bin/python scripts/strict-schema-fixtures.py
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Annotated, Any, Literal
from uuid import UUID

from openai.lib._pydantic import to_strict_json_schema
from pydantic import BaseModel, ConfigDict, Field, RootModel

FIXTURES = Path(__file__).resolve().parent.parent / "Tests" / "StrictSchemaFixtures"


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ParityCustomer(Strict):
    name: str
    email: str | None


class ParityAddress(Strict):
    """Where an order goes."""

    city: str
    zip: str


class ParityOrder(Strict):
    """An order as a model reads it.

    Placed by a customer."""

    note: str = Field(description="Shown on the receipt.")
    id: UUID
    placed_at: datetime | None
    total: float
    homepage: str
    is_gift: bool
    quantity: int = Field(ge=0, le=255)
    status: Literal["open", "shipped"]
    tags: list[str] = []
    priority: int = 3
    weight: float = 1.0
    label: str | None = "draft"
    fallback_status: Literal["open", "shipped"] = "open"
    extra: Any
    customer: ParityCustomer
    ship_to: ParityAddress = Field(description="The address to ship to.")
    bill_to: ParityAddress | None


class ParityCard(Strict):
    title: str


class ParityContent(RootModel[str | list[str] | ParityCard]):
    pass


class ParityCardPayment(Strict):
    """Paid by card."""

    last4: str
    kind: Literal["card"]


class ParityGiftCard(Strict):
    code: str
    amount: int = 50
    kind: Literal["gift-card"]


class ParityPayment(RootModel[ParityCardPayment | ParityGiftCard]):
    """How the order is paid."""


class ParitySearch(Strict):
    query: str = Field(min_length=3, max_length=200)
    page_size: int = Field(ge=1, le=20)
    min_rating: float = Field(ge=0.5)
    region: Annotated[str, Field(pattern="^[a-z]{2}$")] | None
    tags: Annotated[list[Annotated[str, Field(pattern="^[a-z]+$")]], Field(max_length=5)] | None
    ratings: list[Annotated[int, Field(ge=1, le=5)]]
    codes: list[str] = Field(min_length=1)
    rank: int = Field(ge=1, le=10)
    content: ParityContent
    payment: ParityPayment | None


for model in [ParityOrder, ParitySearch, ParityPayment]:
    schema = json.dumps(to_strict_json_schema(model), separators=(",", ":"), ensure_ascii=False)
    (FIXTURES / f"{model.__name__}.json").write_text(f"{schema}\n")
