"""
Pruebas unitarias para la detección de intención en consultas de chat y
prevención de forzado de contexto de adjuntos previos.
"""

from __future__ import annotations

import unittest
from unittest.mock import MagicMock, patch

from services.plan_conversation_service import (
    is_measure_request,
    is_plan_context_query,
)


class TestPlanContextIntent(unittest.TestCase):
    def test_general_technical_questions_do_not_trigger_plan_context(self):
        general_queries = [
            "¿Cuánto tiempo tarda en fraguar el concreto hidráulico?",
            "¿Cuáles son las normas sísmicas en Ciudad de México para zona de lago?",
            "Hola, buenos días",
            "Muchas gracias por tu ayuda",
            "¿Cuál es el f'c típico recomendado para una losa maciza?",
            "¿Qué diferencia existe entre un muro de carga y un tabique divisorio?",
            "¿A qué profundidad se debe desplantar una zapata aislada?",
            "¿Qué tipo de acero de refuerzo se usa en trabes principales?",
        ]
        for q in general_queries:
            with self.subTest(query=q):
                self.assertFalse(
                    is_plan_context_query(q),
                    f"La consulta general '{q}' no debe marcarse como referencia al plano previo.",
                )

    def test_plan_specific_questions_trigger_plan_context(self):
        plan_queries = [
            "Dame las medidas de la cocina y el baño",
            "¿Cuánto mide la puerta de acceso?",
            "¿Qué errores normativos encontraste en el plano?",
            "Sobre el plano anterior, ¿cumple con la iluminación requerida?",
            "¿Cómo puedo corregir las observaciones del archivo adjunto?",
            "¿Cuál es la superficie total de las recámaras?",
            "¿Está bien la distribución de la sala y el comedor?",
            "¿En este espacio cabe un pasillo de 90 cm?",
            "Dime las cotas de las ventanas",
            "¿Qué dice el artículo 150 respecto a las puertas de este croquis?",
        ]
        for q in plan_queries:
            with self.subTest(query=q):
                self.assertTrue(
                    is_plan_context_query(q) or is_measure_request(q),
                    f"La consulta '{q}' debe detectarse como referencia al plano o medidas.",
                )

    def test_measure_request_detection(self):
        self.assertTrue(is_measure_request("¿Cuáles son las medidas?"))
        self.assertTrue(is_measure_request("¿Cuánto mide la recámara?"))
        self.assertTrue(is_measure_request("Dame las dimensiones y área"))
        self.assertFalse(is_measure_request("¿Qué aditivos aceleran el fraguado?"))


if __name__ == "__main__":
    unittest.main()

