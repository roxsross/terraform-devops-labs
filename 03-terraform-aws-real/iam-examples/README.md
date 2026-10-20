# Políticas IAM de ejemplo para el rol de la Lambda

> Navegación: [README general](../../README.md) · volver al [Laboratorio 03 — AWS real](../README.md)

## Objetivo

Revisar o crear el rol IAM que usa la Lambda del laboratorio 03 cuando **no querés o no podés** que Terraform lo cree (`lambda_role_arn` en `terraform.tfvars`). El rol tiene que cumplir dos cosas:

| Archivo | Qué define | Si falta |
|---|---|---|
| `trust-policy.json` | **Quién puede asumir el rol**: el servicio `lambda.amazonaws.com` | Falla la creación de la Lambda (`cannot be assumed by Lambda`) |
| `permissions-policy.json` | **Qué puede hacer la Lambda**: `GetItem`, `PutItem`, `DeleteItem` y `Scan` sobre la tabla, y escribir logs en CloudWatch | La Lambda corre pero responde `500` al acceder a DynamoDB |

La permissions policy es de **mínimo privilegio**: solo las 4 acciones de DynamoDB que usa la app, sobre una sola tabla, y los logs de una sola función. Cuando Terraform crea el rol, adjunta la política administrada `AWSLambdaBasicExecutionRole`, que cubre esos mismos permisos de logs.

## Prerrequisitos

| ✔ | Requisito | Cómo verificarlo |
|---|---|---|
| [ ] | Credenciales cargadas (ver [Credenciales del lab 03](../README.md#credenciales)) | `aws sts get-caller-identity` |
| [ ] | Para **revisar** un rol: `iam:GetRole` e `iam:List*` | `aws iam get-role --role-name <NOMBRE_DEL_ROL>` |
| [ ] | Para **crear** un rol: `iam:CreateRole` e `iam:PutRolePolicy` | Si no los tenés, usá un rol que ya exista en tu sandbox |
| [ ] | Tu `project_name` y `aws_region` definidos | Los mismos de `../terraform.tfvars` |

`permissions-policy.json` usa placeholders que tenés que reemplazar en una **copia**: `<REGION>`, `<ACCOUNT_ID>` y `<PROJECT_NAME>`. El nombre de la tabla es `<PROJECT_NAME>-items` y el log group es `/aws/lambda/<PROJECT_NAME>-api`. No edites el archivo original: así sigue sirviendo como plantilla y no queda tu Account ID en el repositorio.

## Paso a paso

Partís de la raíz del repo, en la terminal donde cargaste las credenciales. Reemplazá los valores de ejemplo por los tuyos.

1. Definí tus valores y obtené el Account ID de la cuenta en la que estás autenticado.

   ```bash
   cd 03-terraform-aws-real/iam-examples
   ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
   REGION="us-east-1"                # la misma que aws_region
   PROJECT_NAME="tf-labs-demo01" # el mismo que project_name
   ROLE="<NOMBRE_DEL_ROL>"            # por ejemplo: tf-labs-demo01-lambda-manual
   ```

2. Generá una copia personalizada de la permissions policy en `/tmp` (fuera del repo).

   ```bash
   sed -e "s/<ACCOUNT_ID>/$ACCOUNT_ID/g" \
       -e "s/<REGION>/$REGION/g" \
       -e "s/<PROJECT_NAME>/$PROJECT_NAME/g" \
       permissions-policy.json > /tmp/permissions-policy.json
   ```

   Salida esperada: ninguna. Revisá el resultado con `cat /tmp/permissions-policy.json`: los ARN ya no tienen `<...>`.

3. Creá el rol con la trust policy (solo si tenés `iam:CreateRole`).

   ```bash
   aws iam create-role \
     --role-name "$ROLE" \
     --assume-role-policy-document file://trust-policy.json
   ```

   Salida esperada: un JSON con `"RoleName"` y `"Arn": "arn:aws:iam::<ACCOUNT_ID>:role/<NOMBRE_DEL_ROL>"`.

4. Agregale la permissions policy inline usando la copia personalizada.

   ```bash
   aws iam put-role-policy \
     --role-name "$ROLE" \
     --policy-name acceso-app \
     --policy-document file:///tmp/permissions-policy.json
   ```

   Salida esperada: ninguna (código de salida 0).

5. Copiá el ARN del rol a `../terraform.tfvars`.

   ```bash
   aws iam get-role --role-name "$ROLE" --query 'Role.Arn' --output text
   ```

   ```hcl
   lambda_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/<NOMBRE_DEL_ROL>"
   ```

   Volvé al [laboratorio 03](../README.md) y seguí con `terraform plan` (debería mostrar `10 to add`).

## Verificación

Para un rol que creaste o que ya existía en tu sandbox:

```bash
# ¿La trust policy permite a Lambda asumir el rol? Debe aparecer "lambda.amazonaws.com".
aws iam get-role --role-name "$ROLE" \
  --query 'Role.AssumeRolePolicyDocument'

# ¿Qué políticas tiene? Buscá acceso a DynamoDB y a CloudWatch Logs.
aws iam list-attached-role-policies --role-name "$ROLE"
aws iam list-role-policies --role-name "$ROLE"
aws iam get-role-policy --role-name "$ROLE" --policy-name acceso-app
```

Al terminar, si creaste el rol a mano, borralo (Terraform no lo administra):

```bash
aws iam delete-role-policy --role-name "$ROLE" --policy-name acceso-app
aws iam delete-role --role-name "$ROLE"
rm -f /tmp/permissions-policy.json
```

## Problemas comunes

| Síntoma | Causa | Solución |
|---|---|---|
| `AccessDenied` en `iam:CreateRole` o `iam:PutRolePolicy` | Tu usuario no puede crear ni modificar roles | Usá un rol que ya exista en el sandbox y revisalo con los comandos de [Verificación](#verificación) |
| `EntityAlreadyExists` | Ya hay un rol con ese nombre | Elegí otro `ROLE` o reutilizá el existente |
| `MalformedPolicyDocument` | Quedó algún `<...>` sin reemplazar o el JSON se rompió | Repetí el paso 2 y revisá `/tmp/permissions-policy.json` |
| La Lambda responde `500` | La permissions policy apunta a otra tabla, región o cuenta | Verificá que `PROJECT_NAME`, `REGION` y `ACCOUNT_ID` coincidan con el `terraform.tfvars` |
| `The role defined for the function cannot be assumed by Lambda` | La trust policy no incluye `lambda.amazonaws.com`, o el rol se acaba de crear | Revisá la trust policy; si es nuevo, esperá unos segundos y repetí `terraform apply` |
