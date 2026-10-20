"""Backend educativo sin dependencias externas empaquetadas.

En Lambda Python 3.13, boto3 está disponible en el runtime administrado.
Para producción conviene empaquetar/pinear dependencias y añadir autenticación,
pruebas y observabilidad avanzada.
"""
import base64
import json
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def json_default(value):
    """Representar los números Decimal de DynamoDB como texto sin perder precisión."""
    if isinstance(value, Decimal):
        return str(value)
    raise TypeError(f"No se puede serializar {type(value).__name__}")


def response(status, data):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(data, ensure_ascii=False, default=json_default),
    }


def lambda_handler(event, context):
    request = event.get("requestContext", {}).get("http", {})
    method = request.get("method", "")
    path = event.get("rawPath", "")
    path_params = event.get("pathParameters") or {}

    try:
        if method == "GET" and path == "/items":
            items = []
            scan_args = {}
            while True:
                result = table.scan(**scan_args)
                items.extend(result.get("Items", []))
                if "LastEvaluatedKey" not in result:
                    break
                scan_args["ExclusiveStartKey"] = result["LastEvaluatedKey"]
            return response(200, {"items": items})

        if method == "GET" and "id" in path_params:
            item = table.get_item(Key={"id": path_params["id"]}).get("Item")
            if item is None:
                return response(404, {"message": "Producto no encontrado"})
            return response(200, item)

        if method == "PUT" and path == "/items":
            raw_body = event.get("body") or "{}"
            if event.get("isBase64Encoded", False):
                raw_body = base64.b64decode(raw_body).decode("utf-8")
            data = json.loads(raw_body)
            if not isinstance(data, dict):
                return response(400, {"message": "Se esperaba un objeto JSON"})
            if not all(key in data for key in ("id", "name", "price")):
                return response(400, {"message": "Faltan id, name o price"})
            if (not isinstance(data["id"], str) or not data["id"].strip()
                or not isinstance(data["name"], str) or not data["name"].strip()
                or isinstance(data["price"], bool)
                or not isinstance(data["price"], (int, float))
                or not (0 <= data["price"] <= 1_000_000_000)):
                return response(400, {"message": "Valores de producto inválidos"})

            # El precio se guarda como texto por simplicidad pedagógica.
            # En producción, definir una estrategia precisa con Decimal.
            table.put_item(Item={
                "id": data["id"],
                "name": data["name"],
                "price": str(data["price"]),
            })
            return response(200, {"message": "Producto guardado"})

        if method == "DELETE" and "id" in path_params:
            table.delete_item(Key={"id": path_params["id"]})
            return response(200, {"message": "Producto eliminado"})

        return response(404, {"message": "Ruta no encontrada"})

    except (ValueError, UnicodeDecodeError, TypeError):
        return response(400, {"message": "Cuerpo JSON inválido"})
    except ClientError:
        # No exponer detalles internos del servicio al cliente.
        return response(500, {"message": "Error al acceder a DynamoDB"})
